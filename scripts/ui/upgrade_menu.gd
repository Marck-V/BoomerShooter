extends Control

# File paths for each weapon
var pistol: Weapon = load("res://resources/weapons/pistol.tres")
var shotgun: Weapon = load("res://resources/weapons/shotgun.tres")
var rifle: Weapon = load("res://resources/weapons/rifle.tres")
var damage_increase = 5

const PISTOL_PATH = "res://resources/weapons/pistol.tres"
const SHOTGUN_PATH = "res://resources/weapons/shotgun.tres"
const RIFLE_PATH = "res://resources/weapons/rifle.tres"

@onready var weapon_nodes := {
	"pistol": $Pistol,
	"shotgun": $Shotgun,
	"rifle": $Rifle
}

@onready var points_label: Label = $HBoxContainer/PointsLabel
@onready var pistol_menu_button: Button = $HBoxContainer/PistolMenuButton
@onready var shotgun_menu_button: Button = $HBoxContainer/ShotgunMenuButton
@onready var rifle_menu_button: Button = $HBoxContainer/RifleMenuButton


func _ready() -> void:
	# Show cursor and pause game
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	points_label.text = "Points: " + str(GlobalVariables.get_points())
	weapon_nodes["pistol"].show()
	GlobalVariables.points_changed.connect(on_points_changed)

	pistol_menu_button.connect("pressed", _on_pistol_menu_button_pressed)
	shotgun_menu_button.connect("pressed", _on_shotgun_menu_button_pressed)
	rifle_menu_button.connect("pressed", _on_rifle_menu_button_pressed)
	# Automatically connect all UpgradeButtons under each weapon node
	for weapon_name in weapon_nodes.keys():
		var root = weapon_nodes[weapon_name]
		var all_nodes = GlobalVariables.get_all_children(root)

		for node in all_nodes:
			if node is UpgradeButton:
				node.pressed.connect(_on_upgrade_button_pressed.bind(node, weapon_name))
				# Debug print to confirm everything is wired correctly
				print("Connected:", node.name, " for ", weapon_name)

	# Disable buttons if upgrades already purchased
	_disable_purchased_upgrades()


func _disable_purchased_upgrades() -> void:
	for weapon_name in weapon_nodes.keys():
		var root = weapon_nodes[weapon_name]
		var all_nodes = GlobalVariables.get_all_children(root)
		for node in all_nodes:
			if node is UpgradeButton and GlobalVariables.has_upgrade(node.upgrade_id):
				node.disabled = true

func _on_pistol_menu_button_pressed() -> void:
	weapon_nodes["shotgun"].hide()
	weapon_nodes["rifle"].hide()
	weapon_nodes["pistol"].show()
	
func _on_shotgun_menu_button_pressed() -> void:
	weapon_nodes["pistol"].hide()
	weapon_nodes["rifle"].hide()
	weapon_nodes["shotgun"].show()

func _on_rifle_menu_button_pressed() -> void:
	weapon_nodes["pistol"].hide()
	weapon_nodes["shotgun"].hide()
	weapon_nodes["rifle"].show()

func on_points_changed(value: int) -> void:
	points_label.text = "Points: " + str(value)

func _on_upgrade_button_pressed(button: UpgradeButton, weapon_name: String) -> void:
	var resource: Resource
	var resource_path: String

	match weapon_name:
		"pistol":
			resource = pistol
			resource_path = PISTOL_PATH
		"shotgun":
			resource = shotgun
			resource_path = SHOTGUN_PATH
		"rifle":
			resource = rifle
			resource_path = RIFLE_PATH

	attempt_upgrade(button, resource, resource_path)


func attempt_upgrade(button: UpgradeButton, resource: Resource, resource_path: String) -> void:
	var id = button.upgrade_id
	var cost = button.cost
	var amount = button.amount
	var property_name = button.property_name
	var is_stat_upgrade = button.is_stat_upgrade  # ← new field in UpgradeButton

	# Prevent repurchasing
	if GlobalVariables.has_upgrade(id):
		print("Upgrade already owned, ID:", id)
		return

	if not GlobalVariables.spend_points(cost):
		print("Not enough points for upgrade:", id)
		return

	# Handle stat-based upgrades (old behavior)
	if is_stat_upgrade:
		if property_name in resource:
			var current = resource.get(property_name)
			resource.set(property_name, current + amount)
			ResourceSaver.save(resource, resource_path)
			print("Upgraded property:", property_name, "→", current + amount)
		else:
			print("Property not found:", property_name)
			return
	else:
		# For behavioral upgrades, no resource modification
		print("Behavioral upgrade purchased:", id)

	# Record upgrade in global save
	GlobalVariables.purchase_upgrade(id)

	# Apply visuals
	button.apply_visual_upgrade()



func _on_reset_button_pressed() -> void:
	# Reset weapon stats
	rifle.damage = 25
	shotgun.shot_count = 5
	shotgun.spread = 5

	ResourceSaver.save(shotgun, SHOTGUN_PATH)
	ResourceSaver.save(rifle, RIFLE_PATH)
	ResourceSaver.save(pistol, PISTOL_PATH)

	# Reset points and upgrades
	GlobalVariables.reset_points()
	GlobalVariables.save_data.upgrades.clear()
	GlobalVariables.save_to_disk()

	# Reset button visuals
	for weapon_name in weapon_nodes.keys():
		var root = weapon_nodes[weapon_name]
		var all_nodes = GlobalVariables.get_all_children(root)
		for node in all_nodes:
			if node is UpgradeButton:
				node.reset()

	print("Upgrades, points, and button visuals reset.")
