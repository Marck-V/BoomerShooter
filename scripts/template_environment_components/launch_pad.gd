extends Area3D

@export var travel_time: float = 0.4
@export var launch_target: Marker3D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return

	if launch_target == null:
		push_warning("LaunchPad has no launch_target set")
		return

	var tween := get_tree().create_tween()
	tween.tween_property(
		body,
		"global_position",
		launch_target.global_position,
		travel_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	print("Launching player to ", launch_target.global_position)
