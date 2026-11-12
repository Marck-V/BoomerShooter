extends Node

var save_data: PlayerData
var infinite_ammo := false   # set by the test room while it's open: spending ammo always succeeds and costs nothing
var carry_ammo_over := false   # set while travelling between levels: the weapons keep their ammo instead of refilling it
var current_weapon
var player
var mouse_sensitivity: float = 20
var psx_strength: float = 1.0
var vignette_strength: float = 0.65
var music_volume: float = 0.2
var sfx_volume: float = 0.2
var fullscreen: bool = false

const SETTINGS_PATH := "user://settings.cfg"
const STORY_SAVE_PATH := "user://player_save.res"
const DEV := "dev"
const STORY := "story"
const UNLOCKABLE := ["pistol", "shotgun", "rifle", "flamethrower", "lightning", "shield"]

var profile := DEV   # DEV or STORY: see set_profile()

# Upgrades that change a weapon stat. The weapon .tres files hold the base stats and are never written to: each
# weapon adds these on top for the upgrades the save says are owned.
const STAT_UPGRADES := {
	"shotgun_precision": {"weapon": "shotgun", "property": "spread", "amount": -2.0},
	"rifle_firerate": {"weapon": "rifle", "property": "cooldown", "amount": -0.05},
}

var _settings_save_timer: Timer

signal points_changed(new_value: int)
signal ammo_changed(weapon_id, new_value: int)
signal health_changed(new_value: int)
signal upgrade_purchased(upgrade_id: String)
signal upgrades_reset
signal unlocks_changed              # a weapon or the shield was handed out, or the profile changed
signal profile_changed(profile: String)
signal quickness_active
signal quickness_ended
signal exit_upgrade_menu
signal parry_landed                 # the shield caught a projectile or a blow: the pistol's Parry Round listens

signal enemy_died(enemy: Node3D)
signal enemy_hit(enemy: Node3D, headshot: bool, killed: bool)   # damage the player should feel: drives the hit marker


func _init():
	# Anything started straight from the editor (a level, the test room) gets the dev profile; the main menu's Play
	# button switches to the story
	_load_profile(DEV)


# --- Profiles ---
# DEV: every weapon, the shield and every upgrade, with plenty of points. It is rebuilt each time it loads and never
# written to disk, so it can't touch the story save. STORY: the real run, saved in user://player_save.res, which starts
# with the pistol only and is handed the rest as the game goes (unlock()).
func set_profile(new_profile: String) -> void:
	if new_profile == profile:
		return
	_load_profile(new_profile)
	profile_changed.emit(profile)
	points_changed.emit(save_data.points)
	for weapon_id in save_data.ammo:
		ammo_changed.emit(weapon_id, save_data.ammo[weapon_id])
	upgrades_reset.emit()
	unlocks_changed.emit()


func _load_profile(new_profile: String) -> void:
	profile = new_profile
	if profile == DEV:
		save_data = PlayerData.new()
		save_data.points = 9999
		for id in save_data.upgrades:
			save_data.upgrades[id] = true
		for id in UNLOCKABLE:
			save_data.unlocked[id] = true
	elif ResourceLoader.exists(STORY_SAVE_PATH):
		print("Existing save found! Loading the save...")
		save_data = ResourceLoader.load(STORY_SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as PlayerData
	else:
		print("No existing save found. Creating new save..")
		save_data = load("res://resources/default_player_save.tres").duplicate(true)
		save_to_disk()
	for weapon_id in ["pistol", "shotgun", "rifle", "flamethrower", "lightning"]:
		if not save_data.ammo.has(weapon_id):
			save_data.ammo[weapon_id] = full_ammo(weapon_id)
		# Saves from before a weapon got its cap can hold more than it allows
		save_data.ammo[weapon_id] = mini(save_data.ammo[weapon_id], max_ammo(weapon_id))


# Starts the story over: the pistol only, no points, no upgrades. The dev profile is untouched.
func reset_story() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STORY_SAVE_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Checkpoints.SAVE_PATH))
	Checkpoints.clear()
	if profile == STORY:
		_load_profile(STORY)
		points_changed.emit(save_data.points)
		for weapon_id in save_data.ammo:
			ammo_changed.emit(weapon_id, save_data.ammo[weapon_id])
		upgrades_reset.emit()
		unlocks_changed.emit()


# Weapons ("pistol", "shotgun", "rifle", "flamethrower", "lightning") and the "shield"
func is_unlocked(id: String) -> bool:
	return save_data.unlocked.get(id, false)


func unlock(id: String) -> void:
	if is_unlocked(id):
		return
	save_data.unlocked[id] = true
	save_to_disk()
	unlocks_changed.emit()

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
		vignette_strength = clampf(cfg.get_value("video", "vignette_strength", vignette_strength), 0.0, 1.0)
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
	cfg.set_value("video", "vignette_strength", vignette_strength)
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

func reset_upgrades():
	save_data.upgrades.clear()
	upgrades_reset.emit()
	save_to_disk()

func save_to_disk():
	if profile == DEV:
		return   # the dev profile is rebuilt every launch and never saved
	ResourceSaver.save(save_data, STORY_SAVE_PATH)

# Puts points, ammo and upgrades back the way a checkpoint recorded them
func restore_progress(points: int, ammo: Dictionary, upgrades: Dictionary):
	save_data.points = points
	save_data.ammo = ammo.duplicate()
	save_data.upgrades = upgrades.duplicate()
	points_changed.emit(save_data.points)
	for weapon_id in save_data.ammo:
		ammo_changed.emit(weapon_id, save_data.ammo[weapon_id])
	upgrades_reset.emit()   # weapons re-read which upgrades they have
	save_to_disk()
	
# Ammo
func get_ammo(weapon: String):
	return save_data.ammo.get(weapon)
	
# Whether a shot of `amount` would go off (without spending anything)
func can_spend_ammo(weapon_id: String, amount: int) -> bool:
	return infinite_ammo or get_ammo(weapon_id) >= amount


func spend_ammo(weapon_id: String, amount: int) -> bool:
	if infinite_ammo:
		return true   # the test room: shots are free and the count stays where it is
	var cur = get_ammo(weapon_id)
	if cur >= amount:
		save_data.ammo[weapon_id] = cur - amount
		ammo_changed.emit(weapon_id, save_data.ammo[weapon_id])
		return true
	return false
	
func add_ammo(weapon_id: String, amount: int):
	var current = save_data.ammo.get(weapon_id, 0)
	var new_value = clamp(current + amount, 0, max_ammo(weapon_id))

	save_data.ammo[weapon_id] = new_value
	ammo_changed.emit(weapon_id, new_value)

func refill_all_ammo():
	for weapon_id in save_data.ammo.keys():
		save_data.ammo[weapon_id] = full_ammo(weapon_id)
		ammo_changed.emit(weapon_id, save_data.ammo[weapon_id])


# Most weapons refill to 50 and can be topped up to 999. The lightning gun is a scarce, horde-clearing weapon: it
# holds 15 at most and its pickups give a few shots, whatever ammo_amount the map put on them.
const AMMO_CAPS := {"lightning": 15}
const AMMO_PICKUP_AMOUNTS := {"lightning": 4}
const DEFAULT_FULL_AMMO := 50
const DEFAULT_MAX_AMMO := 999


func max_ammo(weapon_id: String) -> int:
	return AMMO_CAPS.get(weapon_id, DEFAULT_MAX_AMMO)


func full_ammo(weapon_id: String) -> int:
	return mini(DEFAULT_FULL_AMMO, max_ammo(weapon_id))


func pickup_ammo_amount(weapon_id: String, map_amount: int) -> int:
	return AMMO_PICKUP_AMOUNTS.get(weapon_id, map_amount)
	
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
