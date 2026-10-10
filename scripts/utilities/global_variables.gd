extends Node

var save_data: PlayerData
var current_weapon
var player
var mouse_sensitivity: float = 20
var psx_strength: float = 1.0
var music_volume: float = 0.2
var sfx_volume: float = 0.2
var fullscreen: bool = false

const SETTINGS_PATH := "user://settings.cfg"
var _settings_save_timer: Timer

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
		
	
	for weapon_id in ["pistol", "shotgun", "rifle", "flamethrower", "lightning"]:
		if not save_data.ammo.has(weapon_id):
			save_data.ammo[weapon_id] = 50

func _ready():
	# Emit current value to HUD, etc.
	points_changed.emit(save_data.points)
	load_settings()


# ---- Settings persistence ----
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_volume = clampf(cfg.get_value("audio", "music_volume", music_volume), 0.0, 1.0)
		sfx_volume = clampf(cfg.get_value("audio", "sfx_volume", sfx_volume), 0.0, 1.0)
		mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
		psx_strength = clampf(cfg.get_value("video", "psx_strength", psx_strength), 0.0, 1.0)
		fullscreen = cfg.get_value("video", "fullscreen", fullscreen)

	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("video", "psx_strength", psx_strength)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.save(SETTINGS_PATH)


# Coalesces rapid changes (dragging a slider) into one write shortly after the last one.
func request_settings_save() -> void:
	if _settings_save_timer == null:
		_settings_save_timer = Timer.new()
		_settings_save_timer.one_shot = true
		_settings_save_timer.wait_time = 0.4
		_settings_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_settings_save_timer.timeout.connect(save_settings)
		add_child(_settings_save_timer)
	_settings_save_timer.start()


func _apply_bus_volume(bus_name: String, linear: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	if bus != -1:
		AudioServer.set_bus_volume_db(bus, linear_to_db(linear))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_settings()

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
