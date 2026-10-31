extends Control

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
				node.pressed.connect(_on_upgrade_button_clicked.bind(node))
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
	
func _on_upgrade_button_clicked(button: RegUpgradeButton) -> void:
	audio.play()
	# store selection
	selected_button = button

	# update description text from the button
	description_label.text = button.description

	# enable purchase button so player can confirm
	purchase_button.disabled = false


func _on_purchase_button_pressed() -> void:
	audio.play()
	if selected_button == null:
		return

	attempt_upgrade(selected_button)
	_clear_selection()


# Clears the selection and disables purchase until another upgrade is clicked
func _clear_selection() -> void:
	selected_button = null
	purchase_button.disabled = true
	description_label.text = ""


func attempt_upgrade(button: RegUpgradeButton) -> void:
	var id = button.upgrade_id
	var cost = button.cost

	if GlobalVariables.has_upgrade(id):
		print("Upgrade already owned, ID:", id)
		return

	if not GlobalVariables.spend_points(cost):
		print("Not enough points for upgrade:", id)
		return

	GlobalVariables.purchase_upgrade(id)
	button.apply_visual_upgrade()
	points_label.text = "Points: " + str(GlobalVariables.get_points())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		on_close_button_pressed()


func on_close_button_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	GlobalVariables.exit_upgrade_menu.emit()
	if is_instance_valid(self):
		self.queue_free()

func _on_reset_button_pressed() -> void:
	audio.play()
	# Reset points and upgrades (the weapons rebuild their stats from the now empty upgrade list)
	GlobalVariables.reset_points()
	GlobalVariables.reset_upgrades()
	_clear_selection()

	# Reset button visuals
	for weapon_name in weapon_nodes.keys():
		var root = weapon_nodes[weapon_name]
		var all_nodes = GlobalVariables.get_all_children(root)
		for node in all_nodes:
			if node is RegUpgradeButton:
				node.reset()

	print("Upgrades, points, and button visuals reset.")