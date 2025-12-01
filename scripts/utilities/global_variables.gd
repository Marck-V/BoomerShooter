extends Node

var save_data: PlayerData
var current_weapon
var player
var mouse_sensitivity: float = 20

signal points_changed(new_value: int)
signal ammo_changed(weapon_id, new_value: int)
signal health_changed(new_value: int)
signal upgrade_purchased(upgrade_id: String)
signal quickness_active
signal quickness_ended
signal exit_upgrade_menu

signal enemy_died(enemy: Node3D)


func _init():
	# Load from disk or use default save
	if ResourceLoader.exists("user://player_save.res"):
		print("Existing save found! Loading the save...")
		save_data = ResourceLoader.load("user://player_save.res") as PlayerData
	else:
		print("No existing save found. Creating new save..")
		save_data = load("res://resources/default_player_save.tres").duplicate(true)
		save_to_disk()
		
	
	for weapon_id in ["pistol", "shotgun", "rifle"]:
		if not save_data.ammo.has(weapon_id):
			save_data.ammo[weapon_id] = 50

func _ready():
	# Emit current value to HUD, etc.
	points_changed.emit(save_data.points)

# Points
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

# Upgrades
func has_upgrade(id: String) -> bool:
	return save_data.upgrades.get(id, false)

func purchase_upgrade(id: String):
	save_data.upgrades[id] = true
	upgrade_purchased.emit(id)
	save_to_disk()

func save_to_disk():
	ResourceSaver.save(save_data, "user://player_save.res")
	
# Ammo
func get_ammo(weapon: String):
	return save_data.ammo.get(weapon)
	
func spend_ammo(weapon_id: String, amount: int) -> bool:
	var cur = get_ammo(weapon_id)
	if cur >= amount:
		save_data.ammo[weapon_id] = cur - amount
		ammo_changed.emit(weapon_id, save_data.ammo[weapon_id])
		return true
	return false
	
func add_ammo(weapon_id: String, amount: int):
	var current = save_data.ammo.get(weapon_id, 0)
	var max_ammo = 999
	var new_value = clamp(current + amount, 0, max_ammo)

	save_data.ammo[weapon_id] = new_value
	ammo_changed.emit(weapon_id, new_value)

func refill_all_ammo():
	for weapon_id in save_data.ammo.keys():
		var max_ammo = 50
		save_data.ammo[weapon_id] = max_ammo
		ammo_changed.emit(weapon_id, max_ammo)
	
# Health
func get_health():
	return player.health

func add_health(amount: int):
	player.health = clamp(player.health + amount, 0, 100)
	health_changed.emit(player.health)	
	
# Helper Functions
func get_all_children(node) -> Array:
	var nodes : Array = []
	for n in node.get_children():
		if n.get_child_count() > 0:
			nodes.append(n)
			nodes.append_array(get_all_children(n))
		else:
			nodes.append(n)
	return nodes
