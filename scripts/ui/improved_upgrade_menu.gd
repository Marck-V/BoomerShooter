extends Control

# File paths for each weapon
var pistol: Weapon = load("res://resources/weapons/pistol.tres")
var shotgun: Weapon = load("res://resources/weapons/shotgun.tres")
var rifle: Weapon = load("res://resources/weapons/rifle.tres")

const PISTOL_PATH  = "res://resources/weapons/pistol.tres"
const SHOTGUN_PATH = "res://resources/weapons/shotgun.tres"
const RIFLE_PATH   = "res://resources/weapons/rifle.tres"

@onready var weapon_nodes := {
	"pistol": $Panel/TabContainer/Pistol,
	"shotgun": $Panel/TabContainer/Shotgun,
	"rifle": $Panel/TabContainer/Rifle
}

@onready var points_label: Label      = $Panel/PointsLabel
@onready var close_button: TextureButton = $Panel/CloseButton
@onready var purchase_button: Button  = $Panel/PurchaseButton
@onready var description_label: Label = $Panel/DescriptionPanel/DescriptionLabel
@onready var reset_button: Button = $Panel/ResetButton

@onready var audio : AudioStreamPlayer = $AudioStreamPlayer
# currently selected upgrade
var selected_button: RegUpgradeButton = null
var selected_weapon_name: String = ""

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	points_label.text = "Points: " + str(GlobalVariables.get_points())
	GlobalVariables.points_changed.connect(on_points_changed)
	
	purchase_button.disabled = true
	purchase_button.pressed.connect(_on_purchase_button_pressed)

	reset_button.pressed.connect(_on_reset_button_pressed)

	close_button.connect("pressed", on_close_button_pressed)
	# Automatically connect all RegUpgradeButtons under each weapon node
	for weapon_name in weapon_nodes.keys():
		var root = weapon_nodes[weapon_name]
		var all_nodes = GlobalVariables.get_all_children(root)

		for node in all_nodes:
			if node is RegUpgradeButton:
				node.pressed.connect(_on_upgrade_button_clicked.bind(node, weapon_name))
				print("Connected:", node.name, " for ", weapon_name)

	_disable_purchased_upgrades()


func _disable_purchased_upgrades() -> void:
	for weapon_name in weapon_nodes.keys():
		var root = weapon_nodes[weapon_name]
		var all_nodes = GlobalVariables.get_all_children(root)
		for node in all_nodes:
			if node is RegUpgradeButton and GlobalVariables.has_upgrade(node.upgrade_id):
				node.disabled = true

func on_points_changed(new_points: int) -> void:
	points_label.text = "Points: " + str(new_points)
	
func _on_upgrade_button_clicked(button: RegUpgradeButton, weapon_name: String) -> void:
	audio.play()
	# store selection
	selected_button = button
	selected_weapon_name = weapon_name

	# update description text from the button
	description_label.text = button.description

	# enable purchase button so player can confirm
	purchase_button.disabled = false


func _on_purchase_button_pressed() -> void:
	audio.play()
	if selected_button == null:
		return

	var resource: Resource
	var resource_path: String

	match selected_weapon_name:
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
			print("Unknown weapon:", selected_weapon_name)
			return

	attempt_upgrade(selected_button, resource, resource_path)

	# after buying, clear selection and disable purchase until another upgrade is clicked
	selected_button = null
	selected_weapon_name = ""
	purchase_button.disabled = true
	description_label.text = ""


func attempt_upgrade(button: RegUpgradeButton, resource: Resource, resource_path: String) -> void:
	var id = button.upgrade_id
	var cost = button.cost
	var amount = button.amount
	var property_name = button.property_name
	var is_stat_upgrade = button.is_stat_upgrade

	if GlobalVariables.has_upgrade(id):
		print("Upgrade already owned, ID:", id)
		return

	if not GlobalVariables.spend_points(cost):
		print("Not enough points for upgrade:", id)
		return

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
		print("Upgrade purchased:", id)

	GlobalVariables.purchase_upgrade(id)
	button.apply_visual_upgrade()
	points_label.text = "Points: " + str(GlobalVariables.get_points())

func on_close_button_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GlobalVariables.exit_upgrade_menu.emit()
	if is_instance_valid(self):
		self.queue_free()

func _on_reset_button_pressed() -> void:
	# Reset weapon stats
	rifle.damage = 25
	rifle.cooldown = 0.2
	rifle.max_distance = 40
	shotgun.shot_count = 5
	shotgun.spread = 5
	pistol.damage = 15
	pistol.cooldown = 0.3
	pistol.max_distance = 20

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