extends Control

@onready var weapon_nodes := {
	"pistol": $Panel/TabContainer/Pistol,
	"shotgun": $Panel/TabContainer/Shotgun,
	"rifle": $Panel/TabContainer/Rifle,
	"flamethrower": $Panel/TabContainer/Flamethrower,
	"lightning": $"Panel/TabContainer/Lightning Gun",
	"shield": $Panel/TabContainer/Shield,
}

@onready var tab_container: TabContainer = $Panel/TabContainer
@onready var points_label: Label      = $Panel/PointsLabel
@onready var close_button: TextureButton = $Panel/CloseButton
@onready var purchase_button: Button  = $Panel/PurchaseButton
@onready var description_label: Label = $Panel/DescriptionPanel/DescriptionLabel
@onready var status_label: Label = $Panel/DescriptionPanel/StatusLabel
@onready var reset_button: Button = $Panel/ResetButton

@onready var audio : AudioStreamPlayer = $AudioStreamPlayer

const PURCHASE_SOUND: AudioStream = preload("res://assets/audio/sfx/pickups/money_pickup.mp3")
const DEFAULT_TEXT := "Select an Upgrade to view its description."
const BAD_COLOR := Color(0.72, 0.08, 0.08)      # can't afford it / locked
const GOOD_COLOR := Color(0.08, 0.4, 0.1)       # already owned
const RESET_CONFIRM_TIME := 3.0                 # seconds the second click on Reset stays valid

var purchase_audio: AudioStreamPlayer
# currently selected upgrade (a click), and the one the mouse is over (shown while hovering)
var selected_button: RegUpgradeButton = null
var hovered_button: RegUpgradeButton = null
var reset_armed := false
var reset_token := 0


func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	points_label.text = "Points: " + str(GlobalVariables.get_points())
	GlobalVariables.points_changed.connect(on_points_changed)

	purchase_audio = AudioStreamPlayer.new()
	purchase_audio.stream = PURCHASE_SOUND
	purchase_audio.bus = &"SFX"
	add_child(purchase_audio)

	purchase_button.disabled = true
	purchase_button.pressed.connect(_on_purchase_button_pressed)

	reset_button.pressed.connect(_on_reset_button_pressed)

	close_button.connect("pressed", on_close_button_pressed)
	# Automatically connect all RegUpgradeButtons under each weapon node
	for button in _all_upgrade_buttons():
		button.pressed.connect(_on_upgrade_button_clicked.bind(button))
		# Owned and locked upgrades can't be clicked, but hovering still shows what they are
		button.mouse_entered.connect(_on_button_hovered.bind(button))
		button.mouse_exited.connect(_on_button_unhovered.bind(button))

	# A weapon (or the shield) the player hasn't been given yet has no tab
	for id in weapon_nodes:
		tab_container.set_tab_hidden(weapon_nodes[id].get_index(), not GlobalVariables.is_unlocked(id))
	_open_current_weapon_tab()
	_disable_purchased_upgrades()
	_refresh_info()


func _all_upgrade_buttons() -> Array[RegUpgradeButton]:
	var buttons: Array[RegUpgradeButton] = []
	for weapon_name in weapon_nodes.keys():
		for node in GlobalVariables.get_all_children(weapon_nodes[weapon_name]):
			if node is RegUpgradeButton:
				buttons.append(node)
	return buttons


# The menu opens on the tab of the weapon in hand
func _open_current_weapon_tab() -> void:
	var node: Node = weapon_nodes.get(GlobalVariables.current_weapon)
	if node:
		tab_container.current_tab = node.get_index()


func _disable_purchased_upgrades() -> void:
	for button in _all_upgrade_buttons():
		button.refresh_state()


func on_points_changed(new_points: int) -> void:
	points_label.text = "Points: " + str(new_points)
	_refresh_info()


func _on_upgrade_button_clicked(button: RegUpgradeButton) -> void:
	audio.play()
	selected_button = button
	_refresh_info()


func _on_button_hovered(button: RegUpgradeButton) -> void:
	hovered_button = button
	_refresh_info()


func _on_button_unhovered(button: RegUpgradeButton) -> void:
	if hovered_button == button:
		hovered_button = null
	_refresh_info()


# The description panel and the Purchase button follow the hovered upgrade, or else the selected one:
# its name, cost against the points you have, what it does, and why you can't buy it if you can't
func _refresh_info() -> void:
	var shown := hovered_button if hovered_button != null else selected_button
	if shown == null:
		description_label.text = DEFAULT_TEXT
		status_label.text = ""
	else:
		var points := GlobalVariables.get_points()
		var text := "%s\n" % shown.text
		var status := ""
		var status_color := BAD_COLOR
		match shown.state:
			RegUpgradeButton.State.OWNED:
				text += "Owned\n"
				status = "Owned."
				status_color = GOOD_COLOR
			RegUpgradeButton.State.LOCKED:
				text += "Cost: %d points\n" % shown.cost
				status = "Locked: buy %s first." % shown.requirement_name()
			_:
				text += "Cost: %d points (you have %d)\n" % [shown.cost, points]
				if points < shown.cost:
					status = "Need %d more points." % (shown.cost - points)
		text += "\n" + shown.description
		description_label.text = text
		status_label.text = status
		status_label.add_theme_color_override("font_color", status_color)

	# Purchase follows the selection (not the hover), and only lights up when it can actually be bought
	purchase_button.disabled = selected_button == null \
			or selected_button.state != RegUpgradeButton.State.AVAILABLE \
			or GlobalVariables.get_points() < selected_button.cost


func _on_purchase_button_pressed() -> void:
	if selected_button == null:
		return
	if attempt_upgrade(selected_button):
		purchase_audio.play()
	else:
		audio.play()
	_clear_selection()


# Clears the selection and disables purchase until another upgrade is clicked
func _clear_selection() -> void:
	selected_button = null
	_refresh_info()


func attempt_upgrade(button: RegUpgradeButton) -> bool:
	var id = button.upgrade_id
	var cost = button.cost

	if GlobalVariables.has_upgrade(id):
		return false

	if not GlobalVariables.spend_points(cost):
		return false

	GlobalVariables.purchase_upgrade(id)
	button.apply_visual_upgrade()
	points_label.text = "Points: " + str(GlobalVariables.get_points())
	return true


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


# Reset wipes every upgrade AND the points (nothing is refunded), so it asks twice: the first click arms it and the
# second, within a few seconds, does it
func _on_reset_button_pressed() -> void:
	audio.play()
	if not reset_armed:
		reset_armed = true
		reset_button.text = "Sure? Click again"
		reset_token += 1
		var token := reset_token
		get_tree().create_timer(RESET_CONFIRM_TIME, true, false, true).timeout.connect(func():
			if is_instance_valid(self) and token == reset_token:
				_disarm_reset())
		return
	_disarm_reset()

	# Reset points and upgrades (the weapons rebuild their stats from the now empty upgrade list)
	GlobalVariables.reset_points()
	GlobalVariables.reset_upgrades()
	hovered_button = null
	_clear_selection()

	# Reset button visuals
	for button in _all_upgrade_buttons():
		button.reset()
	_refresh_info()


func _disarm_reset() -> void:
	reset_armed = false
	reset_token += 1
	reset_button.text = "Reset"
