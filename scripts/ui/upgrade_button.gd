extends TextureButton
class_name UpgradeButton

@onready var panel: Panel = $Panel
@onready var label: Label = $MarginContainer/Label
@onready var line_2d: Line2D = $Line2D

var level: int = 0:
	set(value):
		level = value
		label.text = str(level) + "/1"

func _ready() -> void:
	if get_parent() is UpgradeButton:
		line_2d.add_point(global_position + size / 2)
		line_2d.add_point(get_parent().global_position + size / 2)

func _on_pressed() -> void:
	level = min(level+1, 1)
	panel.show_behind_parent = true
	line_2d.default_color = Color(1.0, 1.0, 0.184)

	var skills = get_children()
	for skill in skills:
		if skill is UpgradeButton and level == 1:
			skill.disabled = false
