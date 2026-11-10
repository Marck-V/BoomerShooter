extends Control

# Damage direction indicator: when something hurts the player, a red arrow appears in a ring round the crosshair
# pointing at it. The arrow follows the source as the player turns (and as the source moves), so it always guides
# you to whatever hit you. It stays for HOLD_TIME, then fades out. A source that hits again gets its time refreshed
# rather than a second arrow. Added to the HUD in code; the player's `damage_source` signal feeds it.

const HOLD_TIME := 3.0
const FADE_TIME := 0.5
const RING_RADIUS := 120.0          # pixels from the screen centre to the arrow's base
const ARROW_LENGTH := 26.0
const ARROW_HALF_WIDTH := 16.0
const POP_TIME := 0.15              # the arrow starts a little big and settles
const SAME_SPOT := 1.5              # a hit from a point closer than this to a live arrow's point refreshes it
const MAX_ARROWS := 6
const COLOR := Color(1.0, 0.15, 0.1)
const OUTLINE := Color(0.1, 0.0, 0.0)

var arrows: Array[Dictionary] = []   # {source: Node3D or null, point: Vector3, age: float}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# `source` is a Node3D (followed while it lives) or a world position
func add_source(source) -> void:
	var node: Node3D = source if source is Node3D and source.is_inside_tree() else null
	var point := Vector3.ZERO
	if node != null:
		point = node.global_position
	elif source is Vector3:
		point = source
	else:
		return
	for arrow in arrows:
		var same: bool = (node != null and arrow.source == node) or (node == null and arrow.source == null and arrow.point.distance_to(point) < SAME_SPOT)
		if same:
			arrow.age = 0.0
			arrow.point = point
			return
	arrows.append({"source": node, "point": point, "age": 0.0})
	if arrows.size() > MAX_ARROWS:
		arrows.pop_front()


func _process(delta: float) -> void:
	if arrows.is_empty():
		return
	for arrow in arrows:
		arrow.age += delta
		if arrow.source != null:
			if is_instance_valid(arrow.source) and arrow.source.is_inside_tree():
				arrow.point = arrow.source.global_position   # a source that dies, or is taken out of the level, leaves its arrow at the last spot
			else:
				arrow.source = null
	arrows = arrows.filter(func(arrow): return arrow.age < HOLD_TIME + FADE_TIME)
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var to_camera := camera.global_transform.affine_inverse()
	for arrow in arrows:
		var local: Vector3 = to_camera * arrow.point
		# 0 is straight ahead; positive turns clockwise on screen. Looking up or down doesn't change it.
		var angle := atan2(local.x, -local.z)
		var fade := 1.0 - clampf((arrow.age - HOLD_TIME) / FADE_TIME, 0.0, 1.0)
		var pop := 1.0 + 0.35 * (1.0 - clampf(arrow.age / POP_TIME, 0.0, 1.0))
		draw_set_transform(Vector2.ZERO, angle, Vector2.ONE * pop)
		var shape := PackedVector2Array([
			Vector2(0.0, -RING_RADIUS - ARROW_LENGTH),
			Vector2(ARROW_HALF_WIDTH, -RING_RADIUS),
			Vector2(0.0, -RING_RADIUS - ARROW_LENGTH * 0.3),
			Vector2(-ARROW_HALF_WIDTH, -RING_RADIUS),
		])
		draw_colored_polygon(shape, Color(COLOR, fade))
		var outline := shape.duplicate()
		outline.append(shape[0])
		draw_polyline(outline, Color(OUTLINE, fade), 2.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
