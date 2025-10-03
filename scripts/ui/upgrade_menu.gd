extends Control

# File paths for each weapon
var blaster : Weapon = load("res://resources/weapons/pistol.tres")
var shotgun : Weapon = load("res://resources/weapons/shotgun.tres")
var rifle : Weapon = load("res://resources/weapons/rifle.tres")
var damage_increase = 5

const PISTOL_PATH = "res://resources/weapons/pistol.tres"
const SHOTGUN_PATH = "res://resources/weapons/shotgun.tres"
const RIFLE_PATH = "res://resources/weapons/rifle.tres"

# Pistol
@onready var pistol_button_1: UpgradeButton = $Pistol/PistolButton1
@onready var pistol_button_2: UpgradeButton = $Pistol/PistolButton1/PistolButton2
@onready var pistol_button_3: UpgradeButton = $Pistol/PistolButton1/PistolButton2/PistolButton3
# Shotgun
@onready var shotgun_button_1: UpgradeButton = $Shotgun/ShotgunButton1
@onready var shotgun_button_2: UpgradeButton = $Shotgun/ShotgunButton1/ShotgunButton2
@onready var shotgun_button_3: UpgradeButton = $Shotgun/ShotgunButton1/ShotgunButton2/ShotgunButton3
# Rifle
@onready var rifle_button_1: UpgradeButton = $Rifle/RifleButton1
@onready var rifle_button_2: UpgradeButton = $Rifle/RifleButton1/RifleButton2
@onready var rifle_button_3: UpgradeButton = $Rifle/RifleButton1/RifleButton2/RifleButton3
@onready var points_label: Label = $HBoxContainer/PointsLabel

func _ready() -> void:
	# Show cursor and pause game
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	points_label.text = "Points: " + str(GlobalVariables.get_points())

	GlobalVariables.points_changed.connect(on_points_changed)
	pistol_button_1.connect("pressed", _on_pistol_button_1_pressed)
	pistol_button_2.connect("pressed", _on_pistol_button_2_pressed)
	pistol_button_3.connect("pressed", _on_pistol_button_3_pressed)
	shotgun_button_1.connect("pressed", _on_shotgun_button_1_pressed)
	shotgun_button_2.connect("pressed", _on_shotgun_button_2_pressed)
	shotgun_button_3.connect("pressed", _on_shotgun_button_3_pressed)
	rifle_button_1.connect("pressed", _on_rifle_button_1_pressed)
	rifle_button_2.connect("pressed", _on_rifle_button_2_pressed)
	rifle_button_3.connect("pressed", _on_rifle_button_3_pressed)


	# Disable buttons if upgrade already purchased
	if GlobalVariables.has_upgrade("pistol_upgrade1"):
		pistol_button_1.disabled = true
	if GlobalVariables.has_upgrade("shotgun_upgrade1"):
		shotgun_button_1.disabled = true
	if GlobalVariables.has_upgrade("rifle_upgrade1"):
		rifle_button_1.disabled = true


func on_points_changed(value : int):
	points_label.text = "Points: " + str(value)
	

func attempt_upgrade(button: UpgradeButton, resource: Resource, resource_path: String):
	var id = button.upgrade_id
	var cost = button.cost
	var amount = button.amount
	var property_name = button.property_name

	if GlobalVariables.has_upgrade(id):
		print("Upgrade already owned, ID: " , id)
		return

	if not property_name in resource:
		print("Property not found:", property_name)
		return


	if GlobalVariables.spend_points(cost):
		var current = resource.get(property_name)
		resource.set(property_name, current + amount)
		ResourceSaver.save(resource, resource_path)
		GlobalVariables.purchase_upgrade(id)
		button.apply_visual_upgrade()


func _on_reset_button_pressed() -> void:
	# Reset weapon stat
	rifle.damage = 25
	shotgun.shot_count = 5
	ResourceSaver.save(shotgun, SHOTGUN_PATH)

	# Reset points
	GlobalVariables.reset_points()

	# Clear upgrades from save
	GlobalVariables.save_data.upgrades.clear()
	GlobalVariables.save_to_disk()

	# Reset buttons visually and logically
	rifle_button_1.reset()
	rifle_button_2.reset()
	rifle_button_3.reset()

	print("Upgrades, points, and button visuals reset.")

# Pistol
func _on_pistol_button_1_pressed() -> void:
	attempt_upgrade(pistol_button_1, blaster, PISTOL_PATH)

func _on_pistol_button_2_pressed() -> void:
	attempt_upgrade(pistol_button_2, blaster, PISTOL_PATH)

func _on_pistol_button_3_pressed() -> void:
	attempt_upgrade(pistol_button_3, blaster, PISTOL_PATH)
	
# Shotgun
func _on_shotgun_button_1_pressed() -> void:
	attempt_upgrade(shotgun_button_1, shotgun, SHOTGUN_PATH)

func _on_shotgun_button_2_pressed() -> void:
	attempt_upgrade(shotgun_button_2, shotgun, SHOTGUN_PATH)

func _on_shotgun_button_3_pressed() -> void:
	attempt_upgrade(shotgun_button_3, shotgun, SHOTGUN_PATH)

# Rifle
func _on_rifle_button_1_pressed() -> void:
	attempt_upgrade(rifle_button_1, rifle, RIFLE_PATH)

func _on_rifle_button_2_pressed() -> void:
	attempt_upgrade(rifle_button_2, rifle, RIFLE_PATH)

func _on_rifle_button_3_pressed() -> void:
	attempt_upgrade(rifle_button_3, rifle, RIFLE_PATH)
