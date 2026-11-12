extends Area3D

# A TrenchBroom brush entity ("fall_trigger"): a volume under open ledges, bridges and rooftops. A player who drops
# into it has fallen off the map: they are put back on the last solid ground they stood on, minus a little health
# (the same recovery as a very long fall, without the wait). An enemy that ends up in it dies, so a wave can't be left
# waiting on one that was knocked off the level.
# Draw it wide and flat, a few metres below the lowest floor anyone can stand on above it.

const ENEMY_DAMAGE := 100000.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("Player"):
		if body.has_method("fall_off_map"):
			body.fall_off_map()
	elif body.is_in_group("Enemy") and body.has_method("damage"):
		body.damage(ENEMY_DAMAGE)
