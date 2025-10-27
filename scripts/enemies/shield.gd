extends Node3D

signal shield_destroyed

@export var max_hp := 150.0
@export var damage_reduction := 0.5
@export var shield_material : ShaderMaterial

var hp := max_hp
var pending_damage := 0.0
var print_timer : Timer

func _ready():
	print_timer = Timer.new()
	print_timer.one_shot = true
	print_timer.wait_time = 0.01  # 10ms window to batch pellet hits
	print_timer.timeout.connect(_on_print_timeout)
	add_child(print_timer)

func absorb_damage(amount: float) -> float:
	var reduced_damage = amount * damage_reduction
	hp -= reduced_damage
	pending_damage += reduced_damage

	if not print_timer.is_stopped():
		# Timer already running, more pellets adding up this frame
		pass
	else:
		print_timer.start()

	if hp <= 0:
		shield_destroyed.emit()
		queue_free()
		return 0 # Leave uncommented if you want to stop all damage when shield breaks

	# Still return leftover damage normally
	return amount - reduced_damage

func _on_print_timeout():
	print("Shield took ", pending_damage, " total absorbed damage. Remaining Shield HP: ", hp)
	pending_damage = 0.0
