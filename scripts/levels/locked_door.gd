extends AnimatableBody3D

# A TrenchBroom brush entity ("locked_door") that slides down into the floor to open and back up to close.
# starts_open = 0: shut at the start, opens when the wave_trigger with the same "wave" reports the wave is dead.
# starts_open = 1: open at the start (an entrance), shuts when the wave begins and reopens when it is dead.

@export var wave := ""
@export var starts_open: int = 0
@export var open_depth := 4.2
@export var move_time := 1.2

var is_open := false
var closed_y := 0.0
var open_y := 0.0
var tween: Tween


func _ready() -> void:
	sync_to_physics = true
	# The map build positions the node and sets its properties right after it is added
	_setup.call_deferred()


func _setup() -> void:
	closed_y = position.y
	open_y = closed_y - open_depth
	if starts_open == 1:
		position.y = open_y
		is_open = true


func unlock() -> void:
	if not is_open:
		_move(open_y)
		is_open = true


func lock() -> void:
	if is_open:
		_move(closed_y)
		is_open = false


func _move(target_y: float) -> void:
	Audio.play_at(global_position, "assets/sounds/garage_door_open.wav")
	if tween:
		tween.kill()
	tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "position:y", target_y, move_time)
