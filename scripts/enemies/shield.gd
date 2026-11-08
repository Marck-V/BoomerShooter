extends Node3D

const ShieldBreakEffect = preload("res://scripts/enemies/shield_break_effect.gd")
const AURA_SHADER: Shader = preload("res://shaders/enemies/enemy_shield_aura.gdshader")

signal shield_destroyed

@export var max_hp := 150.0
@export var damage_reduction := 0.5 # 50% less damage while shielded
@export var shield_material : ShaderMaterial
# false: the shield soaks up every hit and the enemy behind it is untouched until it breaks.
# true: the share the shield doesn't take goes through to the enemy.
@export var passes_damage_through := false

# The shield's look is a heat aura: a thin flickering shell just outside the enemy's body, drawn by
# shaders/enemies/enemy_shield_aura.gdshader on a second copy of the body's mesh. It heats up (cyan to white-hot) as the
# shield takes damage, flares when it is hit, and blows outward when it breaks. The enemy calls attach_aura() once its
# model exists; enemies that show their shield another way (the Godot boss tints glass over its body) never do.
const HEAT_SMOOTHING := 6.0   # how quickly the shown heat follows the shield's real health
const HIT_FADE_TIME := 0.3
const BURST_TIME := 0.3

var hp := max_hp
var _aura: MeshInstance3D
var _aura_material: ShaderMaterial
var _heat := 0.0
var _hit := 0.0


func _ready() -> void:
	hp = max_hp
	# Shots hit the hitbox; it hands the damage to the enemy this shield belongs to
	var hitbox = get_node_or_null("ShieldHitbox")
	if hitbox:
		hitbox.owner_enemy = get_parent()
	set_process(false)


# Draws the aura round `model`, the enemy's body mesh. A copy of the mesh with its own material, next to the body, so
# the body's own flashes and overlays keep working.
func attach_aura(model: MeshInstance3D) -> void:
	if model == null or model.mesh == null:
		return
	_aura_material = ShaderMaterial.new()
	_aura_material.shader = AURA_SHADER
	_aura = MeshInstance3D.new()
	_aura.mesh = model.mesh
	_aura.skin = model.skin
	_aura.skeleton = model.skeleton   # same parent as the body, so the same path: it follows the body's pose
	_aura.material_override = _aura_material
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model.get_parent().add_child(_aura)
	_aura.transform = model.transform
	set_process(true)


# A hit flares the aura. (Where on the body doesn't matter: it is one shell.)
func flash(_world_point: Vector3, _color: Color) -> void:
	_hit = 1.0
	set_process(true)


func _process(delta: float) -> void:
	if _aura_material == null:
		set_process(false)
		return
	_heat = lerpf(_heat, 1.0 - clampf(hp / max_hp, 0.0, 1.0), 1.0 - exp(-HEAT_SMOOTHING * delta))
	_hit = maxf(_hit - delta / HIT_FADE_TIME, 0.0)
	_aura_material.set_shader_parameter("heat", _heat)
	_aura_material.set_shader_parameter("hit", _hit)


func absorb_damage(amount: float) -> float:
	# Damage that shield takes directly
	var reduced_damage = amount * damage_reduction
	hp -= reduced_damage
	if hp <= 0:
		ShieldBreakEffect.spawn(get_tree(), global_position + Vector3(0, 1.0, 0), true)
		_burst_aura()
		shield_destroyed.emit()
		queue_free()
		return 0 # Leave uncommented if we want the shield to absorb all extra damage

	print("Shield hit for: ", amount, " damage. Shield absorbed ", reduced_damage, " damage. Remaining Shield HP: ", hp)

	# Return how much damage gets through to the enemy
	if not passes_damage_through:
		return 0.0
	return amount - reduced_damage


# The aura goes white-hot and blows outward, then goes. Its own tween: the shield is about to free itself.
func _burst_aura() -> void:
	if _aura == null or not is_instance_valid(_aura):
		return
	var aura := _aura
	var material := _aura_material
	_aura = null
	material.set_shader_parameter("heat", 1.0)
	material.set_shader_parameter("hit", 0.0)
	var tween := aura.create_tween()
	tween.tween_method(func(value: float): material.set_shader_parameter("burst", value), 0.0, 1.0, BURST_TIME)
	tween.tween_callback(aura.queue_free)
