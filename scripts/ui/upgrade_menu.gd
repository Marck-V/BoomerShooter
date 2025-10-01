extends Control

# File paths for each weapon
var blaster : Weapon = load("res://resources/weapons/pistol.tres")
var shotgun : Weapon = load("res://resources/weapons/shotgun.tres")
var rifle : Weapon = load("res://resources/weapons/rifle.tres")
var damage_increase = 5
const BLASTER_PATH = "res://resources/weapons/blaster.tres"
@onready var rifle_button_1: UpgradeButton = $RifleButton1
@onready var rifle_button_2: UpgradeButton = $RifleButton1/RifleButton2
@onready var rifle_button_3: UpgradeButton = $RifleButton1/RifleButton2/RifleButton3
@onready var points_label: Label = $HBoxContainer/PointsLabel

func _ready() -> void:
	# Show cursor and pause game
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	points_label.text = "Points: " + str(GlobalVariables.get_points())

	GlobalVariables.points_changed.connect(on_points_changed)

	if GlobalVariables.has_upgrade("pistol_upgrade1"):
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

	
func _on_rifle_button_1_pressed() -> void:	
	attempt_upgrade(rifle_button_1, blaster, BLASTER_PATH)


func _on_reset_button_pressed() -> void:
	# Reset weapon stat
	blaster.damage = 25
	blaster.shot_count = 5
	ResourceSaver.save(blaster, BLASTER_PATH)

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


func _on_rifle_button_2_pressed() -> void:
	attempt_upgrade(rifle_button_2, blaster, BLASTER_PATH)


func _on_rifle_button_3_pressed() -> void:
	attempt_upgrade(rifle_button_3, blaster, BLASTER_PATH)
