extends Node

var save_data: PlayerVariables
signal points_changed(new_value: int)

func _ready():
	# Load from disk or use default save
	if ResourceLoader.exists("user://player_save.res"):
		save_data = ResourceLoader.load("user://player_save.res") as PlayerVariables
	else:
		save_data = load("res://resources/default_player_save.tres").duplicate(true)
		save_to_disk()

	# Emit current value to HUD, etc.
	points_changed.emit(save_data.points)

func add_points(amount: int):
	save_data.points += amount
	points_changed.emit(save_data.points)
	save_to_disk()

func spend_points(amount: int) -> bool:
	if save_data.points >= amount:
		save_data.points -= amount
		points_changed.emit(save_data.points)
		save_to_disk()
		return true
	return false

func get_points() -> int:
	return save_data.points
	
func reset_points():
	save_data.points = 0
	points_changed.emit(save_data.points)
	save_to_disk()

func has_upgrade(id: String) -> bool:
	return save_data.upgrades.get(id, false)

func purchase_upgrade(id: String):
	save_data.upgrades[id] = true
	save_to_disk()

func save_to_disk():
	ResourceSaver.save(save_data, "user://player_save.res")
