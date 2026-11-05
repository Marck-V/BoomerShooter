extends CharacterBody3D
class_name EnemyBase

# --- Common Enemy Properties ---
@export var movement_speed: float = 6.0
@export var rotation_speed: float = 5.0
@export var health: float = 100.0
@export var target: Node3D
@export var debug: bool = false
@export var wave: String = ""   # set by map entities: held out of the level until the matching wave_trigger fires
@export var blood_scale: float = 1.0 # how thick this enemy's blood is: bigger enemies bleed fatter streaks and bigger splats
@export var dummy: bool = false # a training dummy: stands still and never attacks, but can be hit and killed like any enemy

var shield: Node = null
var original_materials: Array[Material] = []
var shield_material: ShaderMaterial = preload("res://shaders/enemies/glass_shader.tres")
const HIT_FLASH_SHADER: Shader = preload("res://shaders/enemies/hit_flash.gdshader")
const HIT_FLASH_RADIUS := 0.55
const HIT_FLASH_HOLD := 0.06     # seconds at full brightness, so it registers before it fades
const HIT_FLASH_TIME := 0.18
const HIT_FLASH_COLOR := Color(1.0, 0.95, 0.85)   # the shader's default: weapons with their own look pass another
var hit_flash_material: ShaderMaterial
var hit_flash_tween: Tween
var hit_flash_points: Array[Vector3] = []
var hit_flash_target: ShaderMaterial

# Visual-only flinch: jolts the model node, never the enemy body, so movement is unaffected.
@onready var model_root: Node3D = _find_model_root()
const FLINCH_SHOVE := 0.16      # meters the model is knocked back
const FLINCH_TILT := 0.16       # radians the model tips back
const FLINCH_TIME := 0.16       # seconds to ease back to rest
const FLINCH_MAX_STACK := 2.0
var model_rest := Transform3D.IDENTITY
var flinch_tween: Tween
var flinch_axis := Vector3.RIGHT
var flinch_offset := Vector3.ZERO
var flinch_amount := 0.0
var hit_flash_active := false
const HIT_FLASH_MAX_POINTS := 8
var destroyed: bool = false
var should_move := false

var attack_animation_enter: String = ""
var attack_animation_action: String = "Sword_Attack"
var attack_animation_exit: String = ""
var attack_idle_animation: String = "Idle"

var is_attacking := false
var is_dodging := false  # set by dodging enemies: the model is hidden for the duration of the dodge
const REAPPEAR_FLASH_COLOR := Color(1.8, 1.8, 2.2)  # over 1.0 so the glow picks it up
const REAPPEAR_FLASH_TIME := 0.25
var reappear_flash_material: StandardMaterial3D
var reappear_flash_tween: Tween

# --- State Machine ---
var state = null
var states = {}

# --- References (set in subclasses) ---
@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var anim: AnimationPlayer = _find_anim()
@onready var model: MeshInstance3D = _find_model()
@onready var attack_start_cooldown: Timer = get_node_or_null("AttackStartCooldown")
@onready var audio_player: Node3D = get_node_or_null("AudioPlayer")

# --- Shield ---
@export var has_shield: bool = false
# true: the shield shows as the crystal cage around the enemy (models/enemy_shield). false: the enemy's body turns to
# glass instead (the Godot boss, whose phases tint that glass).
@export var shield_cage: bool = true
const SHIELD_SCENE: PackedScene = preload("res://scenes/enemies/shield.tscn")

# Signal
#signal enemy_died(enemy: EnemyBase)

# ---------------------------
# Lifecycle
# ---------------------------
func _ready():
	model_rest = model_root.transform
	states = get_state_definitions()
	change_state("Idle")
	make_mesh_materials_unique(model)
	cache_original_materials()
	initialize_shield()
	
	add_to_group("Enemy")
	# Enemies spawned by map entities have no target wired in the scene, so find the player
	_resolve_target.call_deferred()
	
	_setup_navigation()
	nav.velocity_computed.connect(Callable(_on_velocity_computed))
	nav.link_reached.connect(_on_link_reached)


# Avoidance settings. Enemies that move the body themselves (the boss) override this.
func _setup_navigation() -> void:
	nav.avoidance_enabled = true
	nav.radius = 0.35  # Personal space
	nav.neighbor_distance = 10  # Look for enemies within 5m
	nav.max_neighbors = 10  # Max enemies to consider
	nav.time_horizon_agents = 1.0  # Prediction time
	nav.max_speed = movement_speed
	nav.avoidance_layers = 1
	nav.avoidance_mask = 1


# ---------------------------
# Navigation links (jumpable gaps)
# ---------------------------
# Set by the agent when it reaches a NavigationLink3D: the link's entry and exit points. An enemy with a
# "Jump" state takes the jump while chasing; the others ignore links.
var pending_link := {}
var jump_ready_msec := 0   # no new jump before this time, so the agent can't re-trigger on the link it just crossed


func _on_link_reached(details: Dictionary) -> void:
	if destroyed or not states.has("Jump") or Time.get_ticks_msec() < jump_ready_msec:
		return
	if state != states.get("Chase") or not _can_jump():
		return
	pending_link = details
	# The signal fires from inside the chase state's update: switch once that has finished, or its remaining
	# lines would go on to apply walking velocity to the jumping enemy
	_start_jump.call_deferred()


func _start_jump() -> void:
	if not destroyed and state == states.get("Chase"):
		change_state("Jump")


func _can_jump() -> bool:
	return not is_attacking and not is_dodging


# Uses the player when no target was assigned in the editor. Deferred so the player has entered the tree.
func _resolve_target() -> void:
	# Deferred, so the enemy may have been removed (held back by a wave trigger, or freed) before this runs
	if not is_inside_tree() or is_instance_valid(target) or destroyed:
		return
	var player := get_tree().get_first_node_in_group("Player") as Node3D
	if player == null:
		return
	target = player
	# The vision area may already overlap the player, which fired body_entered before a target existed
	if has_node("VisionArea") and $VisionArea.overlaps_body(player) and has_method("_on_body_entered"):
		call("_on_body_entered", player)


# True while the target is inside the enemy's vision area. Enemies without one never see anything this way.
func sees_target() -> bool:
	var vision := get_node_or_null("VisionArea") as Area3D
	return vision != null and vision.monitoring and is_instance_valid(target) and vision.overlaps_body(target)


func _on_velocity_computed(safe_velocity: Vector3):
	# Use the avoidance-adjusted velocity
	if should_move:
		velocity = safe_velocity
		move_and_slide()


func _set_velocity(new_velocity: Vector3):
	if nav.avoidance_enabled:
		set_velocity(new_velocity)
	else:
		_on_velocity_computed(new_velocity)


func _physics_process(delta):
	if Time.get_ticks_msec() < shove_hold_until_msec:
		return
	_stay_on_navmesh()
	if state and state.has_method("update"):
		state.update(delta)


# Enemies have no gravity, so anything that carries one past a ledge or up a wall (a lunge, knockback, avoidance)
# would leave it hanging there. This catches every kind of movement by putting it back on the navigation mesh.
const NAVMESH_MAX_DRIFT := 0.15     # further sideways off the mesh than this gets corrected (slopes read as a little drift)
const NAVMESH_MAX_HOVER := 0.75     # the same for height: it normally stands a little off the mesh's height
const NAVMESH_MAX_CORRECTION := 2.0 # further than this it isn't a drift (no mesh here, placed off it): leave it alone


func _stay_on_navmesh() -> void:
	if destroyed or not _keeps_to_navmesh():
		return
	var map := nav.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return
	var closest := NavigationServer3D.map_get_closest_point(map, global_position)
	if closest.distance_to(global_position) > NAVMESH_MAX_CORRECTION:
		return
	var corrected := global_position
	if Vector2(closest.x - corrected.x, closest.z - corrected.z).length() > NAVMESH_MAX_DRIFT:
		corrected.x = closest.x
		corrected.z = closest.z
	if absf(closest.y - corrected.y) > NAVMESH_MAX_HOVER:
		corrected.y = closest.y
	global_position = corrected


# Roughly how much space the body takes up, in metres: x is its radius and y its height from the feet. Read from the
# body's collision capsule. Enemies whose model is bigger than that override it.
func body_size() -> Vector2:
	for child in get_children():
		var collider := child as CollisionShape3D
		if collider != null and collider.shape is CapsuleShape3D:
			var capsule := collider.shape as CapsuleShape3D
			var body_scale := collider.global_basis.get_scale().y
			return Vector2(capsule.radius, capsule.height + collider.position.y - capsule.height * 0.5) * body_scale
	return Vector2(0.35, 1.75)


# Off for jumps, which leave the mesh on purpose. Enemies that aren't bound to the floor override this.
func _keeps_to_navmesh() -> bool:
	return state != states.get("Jump")


# Hides or shows the enemy's visuals; hitboxes keep working. Showing it again after a dodge flashes it in.
func set_dodge_vanished(vanished: bool) -> void:
	var was_vanished := not model_root.visible
	model_root.visible = not vanished
	if shield and is_instance_valid(shield) and shield is Node3D:
		shield.visible = not vanished
	if was_vanished and not vanished:
		_play_reappear_flash()


# A bright overlay across every mesh of the enemy that fades out, so it flashes into view
func _play_reappear_flash() -> void:
	if reappear_flash_material == null:
		reappear_flash_material = StandardMaterial3D.new()
		reappear_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		reappear_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	reappear_flash_material.albedo_color = Color(REAPPEAR_FLASH_COLOR, 0.95)
	for mesh in model_root.find_children("*", "GeometryInstance3D", true, false):
		(mesh as GeometryInstance3D).material_overlay = reappear_flash_material

	if reappear_flash_tween:
		reappear_flash_tween.kill()
	reappear_flash_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	reappear_flash_tween.tween_property(reappear_flash_material, "albedo_color:a", 0.0, REAPPEAR_FLASH_TIME)
	reappear_flash_tween.tween_callback(_end_reappear_flash)


func _end_reappear_flash() -> void:
	for mesh in model_root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := mesh as GeometryInstance3D
		if geometry.material_overlay == reappear_flash_material:
			geometry.material_overlay = null


# Where the model and its animation player live. Models that don't use the mannequin's node layout (the boss)
# override these.
func _find_model_root() -> Node3D:
	return $"Enemy_Model"


func _find_anim() -> AnimationPlayer:
	return $"Enemy_Model/AnimationPlayer"


# The mesh that gets the hit flash, shield material and unique materials. Models without the
# mannequin rig override this.
func _find_model() -> MeshInstance3D:
	return $"Enemy_Model/Rig/Skeleton3D/Mannequin"


# ---------------------------
# Abstract Hooks (subclasses override)
# ---------------------------
func get_state_definitions() -> Dictionary:
	return {}

func perform_attack():
	pass

func can_attack() -> bool:
	return true

func is_in_attack_range() -> bool:
	return false  # default, overridden by specific enemies

# Whether it may begin an attack now that it is in range. Enemies that take turns override this.
func can_start_attack() -> bool:
	return true

# Where the chase state paths to, how fast and whether it looks at the target on the way
func chase_destination() -> Vector3:
	return target.global_position

func chase_speed() -> float:
	return movement_speed

func chase_faces_target() -> bool:
	return false


# ---------------------------
# Damage & Death
# ---------------------------
func damage(amount: float, multiplier: float = 1.0):
	if destroyed:
		return
	var dmg := amount * multiplier
	var shielded := shield != null and is_instance_valid(shield)
	if shield:
		dmg = shield.absorb_damage(dmg)
	
	health -= clamp(dmg, 0.0, health)
	#print("Enemy took damage: ", dmg, " Remaining health: ", health)
	if health <= 0.0 and not destroyed:
		GlobalVariables.enemy_died.emit(self)
		change_state("Dead")
	elif not shielded:
		# The head and neck hurtboxes have a multiplier above 1
		_play_hit_reaction(multiplier > 1.0)
	_report_hit(multiplier > 1.0, shielded)


# Damage over time (burning, the flamethrower's ticks): only a kill is reported, not every tick
func damage_silently(amount: float) -> void:
	silent_damage = true
	damage(amount)
	silent_damage = false


# A shield answers hits with its own clang, so only a hit that reaches the body gets the marker
func _report_hit(headshot: bool, shielded: bool) -> void:
	if destroyed or not (shielded or silent_damage):
		GlobalVariables.enemy_hit.emit(self, headshot, destroyed)


# ---------------------------
# Shove
# ---------------------------
# Throws the enemy out to `radius` from a point and holds it there for a moment, so the space around the point stays
# clear. It goes straight away from the point if that lands on floor with no wall in between, otherwise the nearest
# direction that does. If there is none it stays put: with no gravity it would float off a ledge.
const SHOVE_TIME := 0.2
const SHOVE_HOLD_TIME := 0.7
const SHOVE_ANGLES := [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]
const SHOVE_FLOOR_DEPTH := 2.5
var shove_tween: Tween
var shove_hold_until_msec := 0


func shove_from(point: Vector3, radius: float) -> void:
	if destroyed:
		return
	var away := global_position - point
	away.y = 0.0
	if away.length() < 0.05:
		away = Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)   # right on top of the point: any way out will do
	away = away.normalized()
	for angle: float in SHOVE_ANGLES:
		var landing := point + away.rotated(Vector3.UP, deg_to_rad(angle)) * radius
		landing.y = global_position.y
		if _can_shove_to(point, landing):
			_start_shove(landing)
			return


func _can_shove_to(point: Vector3, landing: Vector3) -> bool:
	var tree := get_tree()
	var height := Vector3.UP * 1.0
	var from := Vector3(point.x, landing.y, point.z) + height
	if not PhysicsLayers.surface_ray(tree, from, landing + height).is_empty():
		return false   # a wall in the way
	return not PhysicsLayers.surface_ray(tree, landing + height, landing + Vector3.DOWN * SHOVE_FLOOR_DEPTH).is_empty()


func _start_shove(landing: Vector3) -> void:
	shove_hold_until_msec = Time.get_ticks_msec() + int((SHOVE_TIME + SHOVE_HOLD_TIME) * 1000.0)
	velocity = Vector3.ZERO
	_on_shoved()
	if shove_tween:
		shove_tween.kill()
	shove_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	shove_tween.tween_property(self, "global_position", landing, SHOVE_TIME)


# Subclasses stop what they were doing here (a punch that is under way)
func _on_shoved() -> void:
	pass


# ---------------------------
# Hit reactions
# ---------------------------
# A short flinch animation when the enemy is hurt: Hit_Head for head and neck hits, Hit_Chest for the rest.
# It never cuts into an attack, dodge or stun, and has a cooldown so rapid fire doesn't hold the enemy in it.
const HIT_REACTION_COOLDOWN := 0.45
var silent_damage := false
var hit_reaction_ready_msec := 0


func _play_hit_reaction(head: bool) -> void:
	if destroyed or anim == null or Time.get_ticks_msec() < hit_reaction_ready_msec or not _can_play_hit_reaction():
		return
	var reaction := "Hit_Head" if head else "Hit_Chest"
	if not anim.has_animation(reaction):
		return  # models without these clips (the flyer) just keep the code-driven jolt
	hit_reaction_ready_msec = Time.get_ticks_msec() + int(HIT_REACTION_COOLDOWN * 1000.0)

	# Go back to whatever was playing, or to Idle if that was a one-shot
	var previous := anim.current_animation
	var resume := "Idle"
	if previous != "" and anim.has_animation(previous) and previous != reaction:
		if previous == attack_idle_animation or anim.get_animation(previous).loop_mode != Animation.LOOP_NONE:
			resume = previous
	anim.play(reaction)
	anim.queue(resume)


# Subclasses add their own conditions (a lunging or stunned enemy is not interrupted)
func _can_play_hit_reaction() -> bool:
	if is_attacking or is_dodging:
		return false
	var current := anim.current_animation
	if current != "" and anim.is_playing() and current in [attack_animation_enter, attack_animation_action, attack_animation_exit]:
		return false
	return true


# ---------------------------
# Localized Hit Flash
# ---------------------------
func flinch(world_point: Vector3, strength := 1.0) -> void:
	if destroyed or is_attacking or strength <= 0.0:
		return

	# Direction the shot travelled: from the player through the hit point, flattened
	var from_position := global_position + global_basis.z
	if GlobalVariables.player and is_instance_valid(GlobalVariables.player):
		from_position = GlobalVariables.player.global_position
	var away := world_point - from_position
	away.y = 0.0
	if away.length() < 0.01:
		return
	var local_away := (global_basis.inverse() * away).normalized()

	flinch_axis = Vector3.UP.cross(local_away).normalized()
	flinch_offset = local_away * FLINCH_SHOVE
	flinch_amount = minf(flinch_amount + strength, FLINCH_MAX_STACK)

	if flinch_tween:
		flinch_tween.kill()
	_apply_flinch(1.0)
	flinch_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flinch_tween.tween_method(_apply_flinch, 1.0, 0.0, FLINCH_TIME)
	flinch_tween.tween_callback(_end_flinch)


func _apply_flinch(t: float) -> void:
	var amount := flinch_amount * t
	var tipped := Basis(flinch_axis, FLINCH_TILT * amount) * model_rest.basis
	model_root.transform = Transform3D(tipped, model_rest.origin + flinch_offset * amount)


func _end_flinch() -> void:
	flinch_amount = 0.0
	model_root.transform = model_rest


func hit_flash(world_point: Vector3, strength := 1.0, radius_scale := 1.0, color := HIT_FLASH_COLOR) -> void:
	if hit_flash_material == null:
		hit_flash_material = ShaderMaterial.new()
		hit_flash_material.shader = HIT_FLASH_SHADER

	# While shielded, the shield draws the flash instead of the overlay: the cage lights the panes around the hit,
	# the glass body lights up where it was hit.
	var shielded := shield != null and is_instance_valid(shield)
	flinch(world_point, strength * (0.3 if shielded else 1.0))
	if shielded and shield_cage and shield.has_method("flash"):
		shield.flash(world_point, color)
		return
	hit_flash_target = shield_material if shielded else hit_flash_material

	# Hits landing while a flash is still showing (shotgun pellets, rapid fire)
	# stack up as extra glow spots; a fresh flash starts from a clean slate.
	if not hit_flash_active:
		hit_flash_points.clear()
	hit_flash_active = true
	hit_flash_points.append(model.to_local(world_point))
	if hit_flash_points.size() > HIT_FLASH_MAX_POINTS:
		hit_flash_points.pop_front()

	var padded := PackedVector3Array()
	padded.resize(HIT_FLASH_MAX_POINTS)
	for i in hit_flash_points.size():
		padded[i] = hit_flash_points[i]

	var local_scale := model.global_basis.get_scale().x
	hit_flash_target.set_shader_parameter("hit_points", padded)
	hit_flash_target.set_shader_parameter("hit_count", hit_flash_points.size())
	hit_flash_target.set_shader_parameter("radius", HIT_FLASH_RADIUS * radius_scale / maxf(local_scale, 0.001))
	hit_flash_target.set_shader_parameter("intensity", 1.0)
	hit_flash_target.set_shader_parameter("flash_color", color)
	if not shielded:
		model.material_overlay = hit_flash_material

	if hit_flash_tween:
		hit_flash_tween.kill()
	hit_flash_tween = create_tween()
	hit_flash_tween.tween_interval(HIT_FLASH_HOLD)
	hit_flash_tween.tween_method(_set_hit_flash_intensity, 1.0, 0.0, HIT_FLASH_TIME)
	hit_flash_tween.tween_callback(_clear_hit_flash)


func _clear_hit_flash() -> void:
	hit_flash_active = false
	model.material_overlay = null


func _set_hit_flash_intensity(value: float) -> void:
	hit_flash_target.set_shader_parameter("intensity", value)


# ---------------------------
# Unified Shield Initialization
# ---------------------------
func initialize_shield():
	if not has_shield:
		return

	# Each shielded enemy needs its own copy so hit flashes don't light up every shield.
	shield_material = shield_material.duplicate()

	# Check for pre-placed Shield or spawn one
	if has_node("Shield"):
		shield = $Shield
	else:
		var shield_scene = SHIELD_SCENE.instantiate()
		shield_scene.name = "Shield"
		add_child(shield_scene)
		shield = shield_scene

	# Connect once
	if shield.has_signal("shield_destroyed") and not shield.is_connected("shield_destroyed", Callable(self, "_on_shield_destroyed")):
		shield.connect("shield_destroyed", Callable(self, "_on_shield_destroyed"))

	if shield_cage and shield.has_method("fit_to"):
		shield.fit_to(_body_bounds_in(shield))
	apply_shield_material()


# The enemy's body in another node's space, for sizing the shield cage around it. Uses the body collider, which
# matches how the enemy stands; the mesh's own bounds are its rest pose (a T-pose for the humanoids, far too wide).
func _body_bounds_in(node: Node3D) -> AABB:
	for child in get_children():
		var collider := child as CollisionShape3D
		if collider and collider.shape and not collider.disabled:
			var to_node: Transform3D = node.global_transform.affine_inverse() * collider.global_transform
			return to_node * collider.shape.get_debug_mesh().get_aabb()
	return _model_bounds_in(node)


func _model_bounds_in(node: Node3D) -> AABB:
	if model == null:
		return AABB()
	var to_node: Transform3D = node.global_transform.affine_inverse() * model.global_transform
	return to_node * model.get_aabb()

func _on_shield_destroyed():
	remove_shield_material()
	shield = null


# ---------------------------
# Material Handling
# ---------------------------
func apply_shield_material():
	if shield_cage:
		return  # the cage is the shield's look; the body keeps its own materials
	#if has_node("ShieldShader"):
		#$ShieldShader.visible = true
	var mesh := model.mesh
	for i in range(mesh.get_surface_count()):
		model.set_surface_override_material(i, shield_material)

func remove_shield_material():
	if shield_cage:
		return
	#if has_node("ShieldShader"):
		#$ShieldShader.visible = false
	var mesh := model.mesh
	for i in range(min(mesh.get_surface_count(), original_materials.size())):
		model.set_surface_override_material(i, original_materials[i])


# ---------------------------
# Safe Mesh Duplication
# ---------------------------
func make_mesh_materials_unique(mesh_instance: MeshInstance3D):
	# The mesh itself stays shared between enemies: only the materials are copied, as per-instance overrides
	var mesh := mesh_instance.mesh
	if mesh == null:
		return

	for i in range(mesh.get_surface_count()):
		var mat := mesh_instance.get_surface_override_material(i)
		if mat == null:
			mat = mesh.surface_get_material(i)
		if mat:
			mesh_instance.set_surface_override_material(i, mat.duplicate())


# ---------------------------
# Cache Original Materials
# ---------------------------
func cache_original_materials():
	original_materials.clear()
	var mesh := model.mesh
	for i in range(mesh.get_surface_count()):
		var override := model.get_surface_override_material(i)
		if override:
			original_materials.append(override)
		else:
			original_materials.append(mesh.surface_get_material(i))


# ---------------------------
# State Management
# ---------------------------
func change_state(state_name: String):
	if not states.has(state_name):
		return
	if destroyed and state_name != "Dead":
		return  # a corpse stays dead (switching its vision area off, for one, would send it back to Idle)
	if dummy and state_name != "Idle" and state_name != "Dead":
		return  # a dummy never chases, attacks, dodges or jumps
	if state and state.has_method("exit"):
		state.exit()
	state = states[state_name]
	if state and state.has_method("enter"):
		state.enter()
