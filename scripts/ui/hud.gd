extends CanvasLayer

@onready var weapon_info_label: Label = $InGameHUD/WeaponInfoLabel
@onready var health_label: Label = $InGameHUD/HealthLabel
@onready var player: CharacterBody3D = $"../Player"
@onready var upgrade_station: Node3D = $"../UpgradeStation"
@onready var interact_label: HBoxContainer = $InGameHUD/InteractContainer
@onready var points_label: Label = $InGameHUD/PointsLabel
@onready var ammo_label: Label = $InGameHUD/AmmoLabel

@export var speed_effect : ColorRect

var current_weapon: Node3D

func _ready() -> void:
	# Connect to the signal emitted from the Player node
	interact_label.visible = false
	player.weapon_changed.connect(_on_weapon_changed)
	player.health_updated.connect(_on_health_updated)
	GlobalVariables.ammo_changed.connect(on_ammo_changed)
	upgrade_station.get_node("Area3D").connect("body_entered", on_upgrade_station_body_entered)
	upgrade_station.get_node("Area3D").connect("body_exited", on_upgrade_station_body_exit)
	GlobalVariables.points_changed.connect(on_points_changed)
	GlobalVariables.health_changed.connect(_on_health_updated)
	points_label.text = "Points: " + str(GlobalVariables.get_points())
	GlobalVariables.quickness_active.connect(_on_quickness_active)
	GlobalVariables.quickness_ended.connect(_on_quickness_ended)
	GlobalVariables.exit_upgrade_menu.connect(_on_exit_upgrade_menu)

func on_points_changed(value : int):
	points_label.text = "Points: " + str(value)

func _on_health_updated(health):
	health_label.text = str(health) + "%"

# Called when the player emits the weapon_changed signal
func _on_weapon_changed(new_weapon_node):
	current_weapon = new_weapon_node
	ammo_label.text = "x" + str(GlobalVariables.get_ammo(current_weapon.data.weapon_id))
	update_weapon_stats_display()

func on_ammo_changed(weapon_id, _new_value):
	if weapon_id == GlobalVariables.current_weapon:
		ammo_label.text = "x" + str(GlobalVariables.get_ammo(weapon_id))
	
# Updates the label with the current weapon’s stats
func update_weapon_stats_display():
	if current_weapon == null:
		weapon_info_label.text = "No weapon selected."
		return

	weapon_info_label.text = "Weapon Stats:\n"
	weapon_info_label.text += "Damage: " + str(current_weapon.data.damage) + "\n"
	weapon_info_label.text += "Cooldown: " + str(current_weapon.data.cooldown) + "\n"
	weapon_info_label.text += "Max Distance: " + str(current_weapon.data.max_distance) + "\n"
	weapon_info_label.text += "Spread: " + str(current_weapon.data.spread) + "\n"
	weapon_info_label.text += "Shot Count: " + str(current_weapon.data.shot_count)

	

func on_upgrade_station_body_entered(body):
	if body.is_in_group("Player"):
		interact_label.visible = true

func on_upgrade_station_body_exit(body):
	if body.is_in_group("Player"):
		interact_label.visible = false


func show_death_screen():
	$DeathScreen.show_death_screen()
func _on_quickness_active():
	speed_effect.visible = true

func _on_quickness_ended():
	speed_effect.visible = false

func _on_exit_upgrade_menu():
	visible = true