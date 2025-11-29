extends Button
class_name RegUpgradeButton

@onready var line_2d: Line2D = $Line2D

@export var upgrade_id : String = ""
@export var cost : int = 5
@export_multiline var description : String = ""
@export_subgroup("Upgrade Effect")
@export_enum ("cooldown", "max_distance", "damage", "spread", "shot_count") var property_name : String
@export var amount : float = 1.0 ## Amount you want to upgrade the property by
@export var is_stat_upgrade: bool = false  ## True if you want to modify a weapon stat, false if you want the upgrade to unlock a new behavior on the weapon.


var level: int = 0:
	set(value):
		level = value
		# label.text = str(level) + "/1"

func _ready() -> void:
	z_index = 2
	if get_parent() is RegUpgradeButton:
		line_2d.z_index = 1
		line_2d.add_point(global_position + size / 2)
		line_2d.add_point(get_parent().global_position + size / 2)
		
	# Check if this upgrade was previously purchased
	if GlobalVariables.has_upgrade(upgrade_id):
		level = 1
		line_2d.default_color = Color(1.0, 1.0, 0.184)
		disabled = false
	else:
		# Disable until parent is purchased
		if get_parent() is RegUpgradeButton and get_parent().level < 1:
			disabled = true
			
func apply_visual_upgrade():
	level = 1
	line_2d.default_color = Color(1.0, 1.0, 0.184)

	# Enable children
	for skill in get_children():
		if skill is RegUpgradeButton:
			skill.disabled = false
		
func reset():
	level = 0
	disabled = true
	line_2d.default_color = Color(0.18, 0.18, 0.18)  # White or original color