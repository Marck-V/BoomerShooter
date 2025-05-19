extends TextureButton
class_name UpgradeButton

@onready var panel: Panel = $Panel
@onready var label: Label = $MarginContainer/CostLabel
@onready var line_2d: Line2D = $Line2D

@export var upgrade_id : String = ""
var level: int = 0:
	set(value):
		level = value
		label.text = str(level) + "/1"

func _ready() -> void:
	if get_parent() is UpgradeButton:
		line_2d.add_point(global_position + size / 2)
		line_2d.add_point(get_parent().global_position + size / 2)
		
	# Check if this upgrade was previously purchased
	if GlobalVariables.has_upgrade(upgrade_id):
		level = 1
		line_2d.default_color = Color(1.0, 1.0, 0.184)
		disabled = false
		panel.show_behind_parent = true
	else:
		# Disable until parent is purchased
		if get_parent() is UpgradeButton and get_parent().level < 1:
			disabled = true

#func _on_pressed() -> void:
	#level = min(level+1, 1)
	#panel.show_behind_parent = true
	#line_2d.default_color = Color(1.0, 1.0, 0.184)
#
	#var skills = get_children()
	#for skill in skills:
		#if skill is UpgradeButton and level == 1:
			#skill.disabled = false
			
func apply_visual_upgrade():
	level = 1
	panel.show_behind_parent = true
	line_2d.default_color = Color(1.0, 1.0, 0.184)

	# Enable children
	for skill in get_children():
		if skill is UpgradeButton:
			skill.disabled = false
		
func reset():
	level = 0
	disabled = true
	line_2d.default_color = Color(0.18, 0.18, 0.18)  # White or original color
	panel.show_behind_parent = false
