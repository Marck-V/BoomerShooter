extends Camera3D

@onready var fade_rect : ColorRect = $"../FadeRect"

@export var move_speed: float = 2.0
@export var cycle_length: float = 10.0
@export var fade_time: float = 1.0   # used for fade-out and fade-in

var timer: float = 0.0
var starting_position: Vector3

func _ready():
    starting_position = global_position
    fade_rect.self_modulate.a = 0.0   # fully visible


func _process(delta):
    timer += delta

    # Smooth forward movement (no shaking)
    global_position += -global_transform.basis.z * move_speed * delta

    if timer < cycle_length:
        # normal movement time
        return

    elif timer < cycle_length + fade_time:
        # Fade OUT
        _fade_out()

    elif timer < cycle_length + fade_time * 2.0:
        # Fade IN
        _fade_in()

    else:
        # Loop complete → reset
        _reset_cycle()


func _fade_out():
    var t = (timer - cycle_length) / fade_time
    fade_rect.self_modulate.a = clamp(t, 0.0, 1.0)


func _fade_in():
    var t = (timer - (cycle_length + fade_time)) / fade_time
    fade_rect.self_modulate.a = 1.0 - clamp(t, 0.0, 1.0)


func _reset_cycle():
    global_position = starting_position
    fade_rect.self_modulate.a = 0.0
    timer = 0.0
