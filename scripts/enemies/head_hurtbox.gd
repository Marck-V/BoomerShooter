extends Area3D  # or CollisionShape3D / Node3D, depending on your setup

@export var multiplier := 2.0  # double damage for headshots
@export var owner_enemy: Node  # assigned in editor or on ready

func damage(amount: int):
	if owner_enemy and owner_enemy.has_method("damage"):
		print("Headshot!")
		owner_enemy.damage(amount, multiplier)
