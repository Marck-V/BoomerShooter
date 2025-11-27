extends Camera3D

@onready var fade_rect : ColorRect = $"../FadeRect"

@export var move_speed: float = 2.0
@export var cycle_length: float = 10.0
@export var fade_time: float = 1.0   # used for fade-out and fade-in

var timer: float = 0.0
var starting_position: Vector3
var has_reset: bool = false  # track if we've reset this cycle

func _ready():
	starting_position = global_position
	fade_rect.self_modulate.a = 0.0   # fully visible


func _process(delta):
	timer += delta

	# Move the camera during normal time AND fade-in
	if timer < cycle_length + fade_time * 2.0:  
		global_position += -global_transform.basis.z * move_speed * delta

	if timer < cycle_length:
		# Normal movement, no fade
		return

	elif timer < cycle_length + fade_time:
		# Fade OUT
		_fade_out()
		has_reset = false  # ensure reset is ready after fade-out

	elif timer < cycle_length + fade_time * 2.0:
		# Reset camera once after fade-out
		if not has_reset:
			global_position = starting_position
			has_reset = true
		# Fade IN
		_fade_in()

	else:
		# Loop complete → reset timer
		timer = 0.0


func _fade_out():
	var t = (timer - cycle_length) / fade_time
	fade_rect.self_modulate.a = clamp(t, 0.0, 1.0)


func _fade_in():
	var t = (timer - (cycle_length + fade_time)) / fade_time
	fade_rect.self_modulate.a = 1.0 - clamp(t, 0.0, 1.0)
