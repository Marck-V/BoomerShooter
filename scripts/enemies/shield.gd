extends Node3D

const ShieldBreakEffect = preload("res://scripts/enemies/shield_break_effect.gd")
const CAGE_MATERIAL: ShaderMaterial = preload("res://shaders/enemy_shield_material.tres")

signal shield_destroyed

@export var max_hp := 150.0
@export var damage_reduction := 0.5 # 50% less damage while shielded
@export var shield_material : ShaderMaterial
# false: the shield soaks up every hit and the enemy behind it is untouched until it breaks.
# true: the share the shield doesn't take goes through to the enemy.
@export var passes_damage_through := false

# The crystal cage model is an egg centred 1 m up, 0.78 m across its middle and 1.18 m from middle to top (half sizes);
# fit_to() stretches it to wrap the enemy's body with CAGE_CLEARANCE to spare on every side.
const CAGE_HALF_WIDTH := 0.78
const CAGE_HALF_HEIGHT := 1.18
const CAGE_CENTRE_Y := 1.0
const CAGE_CLEARANCE := 0.15
const MAX_HITS := 8
const HIT_FADE_TIME := 0.35
const GEM_SPIN := 1.6 # radians per second
const SHATTER_TIME := 0.9

var hp := max_hp
var _cage: MeshInstance3D
var _gem: Node3D
var _cage_material: ShaderMaterial
var _hit_points := PackedVector3Array()
var _hit_strengths := PackedFloat32Array()
var _last_hit_local := Vector3(0, 1, -1)


func _ready() -> void:
	# Shots hit the hitbox; it hands the damage to the enemy this shield belongs to
	var hitbox = get_node_or_null("ShieldHitbox")
	if hitbox:
		hitbox.owner_enemy = get_parent()

	var enemy := get_parent()
	if enemy and "shield_cage" in enemy and not enemy.shield_cage:
		set_cage_visible(false)

	_cage = get_node_or_null("Model/Cage") as MeshInstance3D
	_gem = get_node_or_null("Model/Gem")
	if _cage:
		# Each shield needs its own copy so a hit on one doesn't light up every shield
		_cage_material = CAGE_MATERIAL.duplicate()
		_cage.material_override = _cage_material
		_cage.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hit_points.resize(MAX_HITS)
	_hit_strengths.resize(MAX_HITS)
	set_process(_gem != null)


# Hides the cage for enemies that show their shield another way (the Godot boss tints glass over its body).
func set_cage_visible(value: bool) -> void:
	var model := get_node_or_null("Model") as Node3D
	if model:
		model.visible = value


# Sizes and centres the cage around the enemy's body. `bounds` is in this shield's space.
func fit_to(bounds: AABB) -> void:
	var model := get_node_or_null("Model") as Node3D
	if model == null or bounds.size == Vector3.ZERO:
		return
	var half_width := maxf(bounds.size.x, bounds.size.z) * 0.5 + CAGE_CLEARANCE
	var half_height := bounds.size.y * 0.5 + CAGE_CLEARANCE
	var sx := half_width / CAGE_HALF_WIDTH
	var sy := half_height / CAGE_HALF_HEIGHT
	model.scale = Vector3(sx, sy, sx)
	var centre := bounds.get_center()
	model.position = Vector3(centre.x, centre.y - CAGE_CENTRE_Y * sy, centre.z)
	if _gem:
		_gem.scale = Vector3(1.0, sx / sy, 1.0)  # keep the gem's own shape when the cage is stretched


# Lights up the panes around a hit. Hits stack while earlier ones are still fading.
func flash(world_point: Vector3, color: Color) -> void:
	if _cage_material == null:
		return
	_last_hit_local = _cage.to_local(world_point)
	var slot := 0
	for i in MAX_HITS:  # reuse the faintest slot
		if _hit_strengths[i] < _hit_strengths[slot]:
			slot = i
	_hit_points[slot] = _last_hit_local
	_hit_strengths[slot] = 1.0
	_cage_material.set_shader_parameter("flash_color", color)
	_cage_material.set_shader_parameter("hit_points", _hit_points)
	_cage_material.set_shader_parameter("hit_strengths", _hit_strengths)
	set_process(true)


func _process(delta: float) -> void:
	if _gem:
		_gem.rotate_y(GEM_SPIN * delta)
	var any := false
	for i in MAX_HITS:
		if _hit_strengths[i] > 0.0:
			_hit_strengths[i] = maxf(_hit_strengths[i] - delta / HIT_FADE_TIME, 0.0)
			any = any or _hit_strengths[i] > 0.0
	if _cage_material:
		_cage_material.set_shader_parameter("hit_strengths", _hit_strengths)
	set_process(any or _gem != null)


func absorb_damage(amount: float) -> float:
	# Damage that shield takes directly
	var reduced_damage = amount * damage_reduction
	hp -= reduced_damage
	if hp <= 0:
		ShieldBreakEffect.spawn(get_tree(), global_position + Vector3(0, 1.0, 0), _cage == null or not _cage.is_visible_in_tree())
		_shatter_cage()
		shield_destroyed.emit()
		queue_free()
		return 0 # Leave uncommented if we want the shield to absorb all extra damage

	print("Shield hit for: ", amount, " damage. Shield absorbed ", reduced_damage, " damage. Remaining Shield HP: ", hp)

	# Return how much damage gets through to the enemy
	if not passes_damage_through:
		return 0.0
	return amount - reduced_damage


# Moves the cage out into the world, where it flies apart pane by pane and frees itself.
func _shatter_cage() -> void:
	if _cage == null or not _cage.is_visible_in_tree() or not is_inside_tree():
		return
	var model := get_node("Model") as Node3D
	var world_transform := model.global_transform
	model.get_parent().remove_child(model)
	get_tree().current_scene.add_child(model)
	model.global_transform = world_transform
	if _gem:
		_gem.queue_free()  # the gem is spent: the pop and sparks cover it
	_hit_strengths.fill(0.0)
	_cage_material.set_shader_parameter("hit_strengths", _hit_strengths)
	_cage_material.set_shader_parameter("shatter_hit", _last_hit_local)
	_cage_material.set_shader_parameter("shatter_length", SHATTER_TIME)
	# The tween belongs to the model, which outlives this shield
	var tween := model.create_tween()
	tween.tween_property(_cage_material, "shader_parameter/shatter_time", SHATTER_TIME, SHATTER_TIME).from(0.0)
	tween.tween_callback(model.queue_free)
