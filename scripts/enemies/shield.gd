extends Node3D

const ShieldBreakEffect = preload("res://scripts/enemies/shield_break_effect.gd")

signal shield_destroyed

@export var max_hp := 150.0
@export var damage_reduction := 0.5 # 50% less damage while shielded
@export var shield_material : ShaderMaterial
# false: the shield soaks up every hit and the enemy behind it is untouched until it breaks.
# true: the share the shield doesn't take goes through to the enemy.
@export var passes_damage_through := false

var hp := max_hp


func _ready() -> void:
	# Shots hit the hitbox; it hands the damage to the enemy this shield belongs to
	var hitbox = get_node_or_null("ShieldHitbox")
	if hitbox:
		hitbox.owner_enemy = get_parent()


func absorb_damage(amount: float) -> float:
	# Damage that shield takes directly
	var reduced_damage = amount * damage_reduction
	hp -= reduced_damage
	if hp <= 0:
		ShieldBreakEffect.spawn(get_tree(), global_position + Vector3(0, 1.0, 0))
		shield_destroyed.emit()
		queue_free()
		return 0 # Leave uncommented if we want the shield to absorb all extra damage

	print("Shield hit for: ", amount, " damage. Shield absorbed ", reduced_damage, " damage. Remaining Shield HP: ", hp)
	
	# Return how much damage gets through to the enemy
	if not passes_damage_through:
		return 0.0
	return amount - reduced_damage
