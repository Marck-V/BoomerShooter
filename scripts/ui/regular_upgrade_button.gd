extends Button
class_name RegUpgradeButton

@onready var line_2d: Line2D = $Line2D

@export var upgrade_id : String = ""
@export var cost : int = 5
@export_multiline var description : String = ""

# An upgrade is available (can be selected and bought), owned (bought: green), or locked (the one before it in its
# chain is not owned yet: grey). Owned and locked buttons are disabled, but the menu still shows their details on hover.
enum State { AVAILABLE, OWNED, LOCKED }
var state := State.AVAILABLE

const OWNED_FILL := Color(0.55, 0.82, 0.55)
const OWNED_EDGE := Color(0.08, 0.32, 0.08)
const OWNED_TEXT := Color(0.05, 0.25, 0.05)
const LOCKED_FILL := Color(0.58, 0.58, 0.58)
const LOCKED_EDGE := Color(0.3, 0.3, 0.3)
const LOCKED_TEXT := Color(0.38, 0.38, 0.38)

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
        refresh_state()


# Works out whether this upgrade is owned, locked behind the one before it, or available, and styles the button to match
func refresh_state() -> void:
    if GlobalVariables.has_upgrade(upgrade_id):
        state = State.OWNED
    elif get_parent() is RegUpgradeButton and not GlobalVariables.has_upgrade((get_parent() as RegUpgradeButton).upgrade_id):
        state = State.LOCKED
    else:
        state = State.AVAILABLE
    disabled = state != State.AVAILABLE
    match state:
        State.OWNED:
            _set_disabled_look(OWNED_FILL, OWNED_EDGE, OWNED_TEXT)
        State.LOCKED:
            _set_disabled_look(LOCKED_FILL, LOCKED_EDGE, LOCKED_TEXT)
        State.AVAILABLE:
            remove_theme_stylebox_override("disabled")
            remove_theme_color_override("font_disabled_color")


func _set_disabled_look(fill: Color, edge: Color, text_color: Color) -> void:
    var box := StyleBoxFlat.new()
    box.bg_color = fill
    box.set_border_width_all(2)
    box.border_color = edge
    add_theme_stylebox_override("disabled", box)
    add_theme_color_override("font_disabled_color", text_color)


# The name of the upgrade that has to be bought before this one ("" if nothing does)
func requirement_name() -> String:
    if get_parent() is RegUpgradeButton:
        return (get_parent() as RegUpgradeButton).text
    return ""


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
    line_2d.default_color = Color(1.0, 1.0, 0.184)
    refresh_state()

    # Buying this unlocks the next upgrade in the chain
    for child in get_children():
        if child is RegUpgradeButton:
            child.refresh_state()


func reset() -> void:
    level = 0
    line_2d.default_color = Color(0.18, 0.18, 0.18)
    refresh_state()   # the first upgrade of each tree can be bought straight away; the rest are locked
