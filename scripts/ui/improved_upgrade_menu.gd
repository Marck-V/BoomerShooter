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
	"pistol": $Panel/TabContainer/Pistol,
	"shotgun": $Panel/TabContainer/Shotgun,
	"rifle": $Panel/TabContainer/Rifle
}


@onready var points_label: Label = $Panel/PointsLabel
@onready var close_button: TextureButton = $Panel/CloseButton
@onready var purchase_button: Button = $Panel/PurchaseButton
@onready var description_label: Label = $Panel/DescriptionPanel/DescriptionLabel

@onready var pistol_button1: Button = $Panel/TabContainer/Pistol/PistolButton1
@onready var pistol_button2: Button = $Panel/TabContainer/Pistol/PistolButton1/PistolButton2
@onready var pistol_button3: Button = $Panel/TabContainer/Pistol/PistolButton1/PistolButton2/PistolButton3

func _ready():
	points_label.text = "Points: " + str(GlobalVariables.get_points())
	purchase_button.connect("pressed", _on_purchase_button_pressed)
	# Automatically connect all RegUpgradeButtons under each weapon node
	for weapon_name in weapon_nodes.keys():
		var root = weapon_nodes[weapon_name]
		var all_nodes = GlobalVariables.get_all_children(root)

		for node in all_nodes:
			if node is RegUpgradeButton:
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
			if node is RegUpgradeButton and GlobalVariables.has_upgrade(node.upgrade_id):
				node.disabled = true

func _on_upgrade_button_pressed(button: RegUpgradeButton, weapon_name: String) -> void:
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
		_:
			print("Unknown weapon:", weapon_name)
			return

	attempt_upgrade(button, resource, resource_path)
func _on_pistol_button1_pressed() -> void:
	purchase_button.disabled = false
	description_label.text = "Every shot from the pistol has a chance to refund some ammo."

func _on_pistol_button2_pressed() -> void:
	purchase_button.disabled = false
	description_label.text = "Piercing shots from the pistol can penetrate enemies."

func _on_pistol_button3_pressed() -> void:
	purchase_button.disabled = false
	description_label.text = "Each successful hit with the pistol has a chance to heal you."

func _on_purchase_button_pressed() -> void:
	return

func attempt_upgrade(button: RegUpgradeButton, resource: Resource, resource_path: String) -> void:
	var id = button.upgrade_id
	var cost = button.cost
	var amount = button.amount
	var property_name = button.property_name
	var is_stat_upgrade = button.is_stat_upgrade  # ← new field in RegUpgradeButton

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
