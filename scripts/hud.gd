extends CanvasLayer

@onready var label: Label = $Label
@onready var health_label: Label = $Health
@onready var player: CharacterBody3D = $"../Player"

var current_weapon: Weapon

func _ready() -> void:
	# Connect to the signal emitted from the Player node
	player.weapon_changed.connect(_on_weapon_changed)
	
	# Optional: set an initial weapon if needed
	# _on_weapon_changed(load("res://weapons/blaster.tres"))

func _on_health_updated(health):
	health_label.text = str(health) + "%"

# Called when the player emits the weapon_changed signal
func _on_weapon_changed(new_weapon: Weapon):
	current_weapon = new_weapon
	update_weapon_stats_display()

# Updates the label with the current weapon’s stats
func update_weapon_stats_display():
	if current_weapon == null:
		return
	label.text = "Weapon Stats:\n"
	label.text += "Damage: " + str(current_weapon.damage) + "\n"
	label.text += "Cooldown: " + str(current_weapon.cooldown) + "\n"
	label.text += "Max Distance: " + str(current_weapon.max_distance) + "\n"
	label.text += "Spread: " + str(current_weapon.spread) + "\n"
	label.text += "Shot Count: " + str(current_weapon.shot_count) + "\n"
	label.text += "Knockback: " + str(current_weapon.knockback)
