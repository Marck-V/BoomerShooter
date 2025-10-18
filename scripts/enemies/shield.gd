extends Node3D

signal shield_destroyed

@export var max_hp := 50.0
@export var damage_reduction := 0.5 # 50% less damage while shielded
@export var shield_material : ShaderMaterial

var hp := max_hp

#@onready var mesh = $MeshInstance3D


func _ready():
	pass
	#if shield_material:
		#mesh.material_override = shield_material
		

func absorb_damage(amount: float) -> float:
	# Damage that shield takes directly
	var reduced_damage = amount * damage_reduction
	hp -= reduced_damage
	if hp <= 0:
		emit_signal("shield_destroyed")
		queue_free()
		
		return 0 # Leave uncommented if we want the shield to absorb all extra damage
	# Return how much damage gets through to the enemy
	return amount - reduced_damage
