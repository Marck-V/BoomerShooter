extends Control

# Dash charges: one bar under the health, split by dividers into a third per dash. Its level is the combined charge of
# the dashes: spending one drains a third of the bar from the right, and recharging fills it back from the left.
# Added to the HUD in code; it reads the player's dash_cooldowns.

const BAR_SIZE := Vector2(90.0, 10.0)   # as wide as the health label above it
const LEFT := 46.0                      # lines up with the health label
const BOTTOM := 30.0                    # distance from the bottom of the screen to the bar's centre line
const DRAIN_SPEED := 8.0                # bar lengths per second it drains when a dash is spent (it fills as fast as the dashes recharge)
const BACK := Color(0.0, 0.0, 0.0, 0.55)
const BORDER := Color(0.0, 0.0, 0.0, 0.85)
const DIVIDER := Color(0.0, 0.0, 0.0, 0.9)
const FILL := Color(0.25, 0.95, 1.0, 1.0)

var player: Node
var level := 1.0       # what is shown: 0 to 1 of the bar


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = LEFT
	offset_right = LEFT + BAR_SIZE.x
	offset_top = -BOTTOM - BAR_SIZE.y * 0.5
	offset_bottom = -BOTTOM + BAR_SIZE.y * 0.5


# The combined charge of every dash, 0 to 1
func _charge() -> float:
	var cooldowns: Array = player.dash_cooldowns
	var full: float = maxf(player.dash_cooldown, 0.001)
	var total := 0.0
	for left in cooldowns:
		total += 1.0 - clampf(float(left) / full, 0.0, 1.0)
	return total / maxf(cooldowns.size(), 1)


func _process(delta: float) -> void:
	if player == null:
		return
	var target := _charge()
	level = target if target >= level else maxf(target, level - DRAIN_SPEED * delta)   # drops smoothly, rises with the recharge
	queue_redraw()


func _draw() -> void:
	if player == null:
		return
	var rect := Rect2(Vector2.ZERO, BAR_SIZE)
	draw_rect(rect, BACK)
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * level, rect.size.y)), FILL)
	var sections: int = player.dash_cooldowns.size()
	for i in range(1, sections):
		var x := rect.size.x * float(i) / sections
		draw_line(Vector2(x, 0.0), Vector2(x, rect.size.y), DIVIDER, 2.0)
	draw_rect(rect, BORDER, false, 2.0)
