extends Button
class_name RegUpgradeButton

@onready var line_2d: Line2D = $Line2D

@export var upgrade_id : String = ""
@export var cost : int = 5
@export_multiline var description : String = ""

@export_subgroup("Upgrade Effect")
@export var is_stat_upgrade: bool = false  # true = stat change, false = behavior
@export_enum("cooldown", "max_distance", "damage", "spread", "shot_count")
var property_name : String
@export var amount : float = 1.0


var level: int = 0:
    set(value):
        level = value


func _ready() -> void:
    z_index = 2

    _update_line()

    if GlobalVariables.has_upgrade(upgrade_id):
        apply_visual_upgrade()
    else:
        if get_parent() is RegUpgradeButton:
            var parent_btn := get_parent() as RegUpgradeButton
            if not GlobalVariables.has_upgrade(parent_btn.upgrade_id):
                disabled = true


func _update_line() -> void:
    if not is_instance_valid(line_2d):
        return

    line_2d.clear_points()

    if get_parent() is RegUpgradeButton:
        var parent_btn := get_parent() as RegUpgradeButton

        line_2d.top_level = true
        line_2d.global_position = Vector2.ZERO
        line_2d.z_index = 0

        var line_x := global_position.x + size.x * 0.5

        var parent_bottom := Vector2(
            line_x,
            parent_btn.global_position.y + parent_btn.size.y
        )
        var my_top := Vector2(
            line_x,
            global_position.y + 30
        )

        line_2d.add_point(parent_bottom)
        line_2d.add_point(my_top)
    else:
        line_2d.hide()

func apply_visual_upgrade() -> void:
    level = 1
    disabled = true
    line_2d.default_color = Color(1.0, 1.0, 0.184)

    for child in get_children():
        if child is RegUpgradeButton:
            child.disabled = false


func reset() -> void:
    level = 0
    disabled = true
    line_2d.default_color = Color(0.18, 0.18, 0.18)
