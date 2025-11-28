extends Node

@export var use_3d: bool = false
@export var num_players := 12
@export var bus := "SFX"

var available: Array = []
var queue: Array = []


func _ready() -> void:
	for i in range(num_players):
		var p

		if use_3d:
			p = AudioStreamPlayer3D.new()
		else:
			p = AudioStreamPlayer.new()

		add_child(p)
		available.append(p)

		p.volume_db = -10
		p.bus = bus

		p.finished.connect(_on_stream_finished.bind(p))


func _on_stream_finished(player) -> void:
	available.append(player)


func _process(_delta: float) -> void:
	if queue.is_empty() or available.is_empty():
		return

	var player = available.pop_front()
	var item = queue.pop_front()

	# Item may be a string or a dictionary
	var stream_path = item.path if typeof(item) == TYPE_DICTIONARY else item
	var pos = item.pos if typeof(item) == TYPE_DICTIONARY and item.has("pos") else null


	player.stream = load(stream_path)
	player.pitch_scale = randf_range(0.9, 1.1)

	if use_3d and pos != null:
		player.global_position = pos

	player.play()


func play(sound_paths: String) -> void:
	var list := sound_paths.split(",")
	var chosen := list[randi() % list.size()].strip_edges()
	queue.append("res://" + chosen)


func play_at(position: Vector3, sound_paths: String) -> void:
	var list := sound_paths.split(",")
	var chosen := list[randi() % list.size()].strip_edges()
	var path := "res://" + chosen

	queue.append({"path": path, "pos": position})
