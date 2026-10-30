extends Area3D

# The part of a shield that shots and thrown shields hit. Like a body hurtbox it forwards damage to its enemy, whose
# damage() lets the shield soak it up, so weapons need no shield-specific damage code.

var owner_enemy: Node  # set by the shield


func damage(amount: float, multiplier: float = 1.0) -> void:
	if is_instance_valid(owner_enemy) and owner_enemy.has_method("damage"):
		owner_enemy.damage(amount, multiplier)
