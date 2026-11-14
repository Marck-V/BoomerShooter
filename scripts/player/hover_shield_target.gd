extends Area3D

# The part of the hovering shield that shots hit. It sits on the enemy hurtbox layer (like the lifesteal orb), so the
# player's hitscan finds it. Weapons hand their shot to the shield through BaseWeapon.damage_hit, so the ricochet keeps
# the weapon's own behaviour (lightning chains, rifle spikes...). Anything else that calls damage() on it directly gets a
# plain ricochet of that damage.

var shield: Node   # the offhand shield that threw it


func _ready() -> void:
	add_to_group("HoverShield")
	collision_layer = 8   # PhysicsLayers.ENEMY_HURTBOX
	collision_mask = 0
	monitoring = false


func damage(amount: float = 0.0, _multiplier: float = 1.0) -> void:
	ricochet(null, amount, global_position)


func ricochet(weapon: Node, amount: float, point: Vector3) -> void:
	if is_instance_valid(shield):
		shield.on_hover_shot(weapon, amount, point)
