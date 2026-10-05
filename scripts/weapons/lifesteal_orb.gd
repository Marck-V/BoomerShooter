extends Area3D

@export var heal_amount := 5
@export var lifespan := 3.0
@export var rise_speed := 2.0
@export var fade_time := 0.5

var age := 0.0
var collected := false


func _ready() -> void:
	add_to_group("LifestealOrb")


func _process(delta: float) -> void:
	age += delta
	global_position.y += rise_speed * delta

	var remaining := lifespan - age
	if remaining <= 0.0:
		queue_free()
	elif remaining <= fade_time:
		scale = Vector3.ONE * (remaining / fade_time)


func damage(_amount = 0, _multiplier = 1.0) -> void:
	if collected:
		return
	collected = true
	GlobalVariables.add_health(heal_amount)
	queue_free()
