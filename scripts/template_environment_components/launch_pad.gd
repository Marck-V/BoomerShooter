@tool
extends Area3D

# The old flat red box sits a little under the pad; the portal replaces it
const PORTAL_HEIGHT := -0.22

@export var travel_time: float = 0.4
@export var launch_target: Marker3D

var portal: LaunchPadPortal

func _ready() -> void:
	var old_mesh := get_node_or_null("MeshInstance3D")
	if old_mesh != null:
		old_mesh.visible = false
	portal = LaunchPadPortal.new()
	portal.position = Vector3(0.0, PORTAL_HEIGHT, 0.0)
	add_child(portal)  # not given an owner, so it is never saved into a scene

	# In the editor the pad only needs to look right
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return

	if launch_target == null:
		push_warning("LaunchPad has no launch_target set")
		return

	portal.play_burst()

	var tween := get_tree().create_tween()
	tween.tween_property(
		body,
		"global_position",
		launch_target.global_position,
		travel_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	print("Launching player to ", launch_target.global_position)
