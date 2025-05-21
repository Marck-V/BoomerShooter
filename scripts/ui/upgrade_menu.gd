extends Control

# File paths for each weapon
var blaster : Weapon = load("res://weapons/blaster.tres")
var repeater : Weapon = load("res://weapons/blaster-repeater.tres")
var damage_increase = 5
const BLASTER_PATH = "res://weapons/blaster.tres"
@onready var rifle_button_1: UpgradeButton = $RifleButton1
@onready var rifle_button_2: UpgradeButton = $RifleButton1/RifleButton2
@onready var rifle_button_3: UpgradeButton = $RifleButton1/RifleButton2/RifleButton3
@onready var points_label: Label = $HBoxContainer/PointsLabel

func _ready() -> void:
	points_label.text = "Points: " + str(GlobalVariables.get_points())

	GlobalVariables.points_changed.connect(on_points_changed)
	
	if GlobalVariables.has_upgrade("blaster_damage"):
		rifle_button_1.disabled = true


func on_points_changed(value : int):
	points_label.text = "Points: " + str(value)
	

func attempt_upgrade(button: UpgradeButton, upgrade_id: String, cost: int, damage_increase: int):
	if GlobalVariables.has_upgrade(upgrade_id):
		print("Upgrade already purchased!")
		return

	if GlobalVariables.spend_points(cost):
		blaster.damage += damage_increase
		ResourceSaver.save(blaster, BLASTER_PATH)
		GlobalVariables.purchase_upgrade(upgrade_id)

		button.apply_visual_upgrade()
		print("Upgrade applied:", upgrade_id)
	else:
		print("Not enough points for:", upgrade_id)

	
func _on_rifle_button_1_pressed() -> void:	
	attempt_upgrade(rifle_button_1, "blaster_damage", 5, 5)


func _on_reset_button_pressed() -> void:
	# Reset weapon stat
	blaster.damage = 25
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
	var cost := 5

	if GlobalVariables.has_upgrade("blaster_damage2"):
		print("Upgrade already purchased!")
		return

	if GlobalVariables.spend_points(cost):
		blaster.damage += damage_increase
		ResourceSaver.save(blaster, BLASTER_PATH)
		GlobalVariables.purchase_upgrade("blaster_damage2")

		rifle_button_2.apply_visual_upgrade()
		print("Rifledamage upgraded!")
	else:
		print("Not enough points.")


func _on_rifle_button_3_pressed() -> void:
	var cost := 5

	if GlobalVariables.has_upgrade("blaster_damage3"):
		print("Upgrade already purchased!")
		return

	if GlobalVariables.spend_points(cost):
		blaster.damage += damage_increase
		ResourceSaver.save(blaster, BLASTER_PATH)
		GlobalVariables.purchase_upgrade("blaster_damage3")

		rifle_button_3.apply_visual_upgrade()
		print("Rifle damage upgraded!")
	else:
		print("Not enough points.")
