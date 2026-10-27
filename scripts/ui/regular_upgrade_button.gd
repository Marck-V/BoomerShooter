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
    # Button sizes are still settling (theme, fonts) during _ready, so the line follows them
    resized.connect(_update_line)
    if get_parent() is RegUpgradeButton:
        get_parent().resized.connect(_update_line)

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

        # Drawn in this button's own coordinates (from the parent's bottom edge to this button's bottom edge, behind
        # it), so it never depends on where the TabContainer has laid out the tab. Global positions are wrong in
        # _ready and in tabs that have not been shown yet.
        line_2d.top_level = false
        line_2d.position = Vector2.ZERO
        line_2d.z_index = -1

        var parent_bottom := Vector2(size.x * 0.5, parent_btn.size.y - position.y)
        var my_bottom := Vector2(size.x * 0.5, size.y)

        line_2d.add_point(parent_bottom)
        line_2d.add_point(my_bottom)
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
