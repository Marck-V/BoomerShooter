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
			p.attenuation_filter_db = 0.0   # far sounds fade but keep their highs: the default filter muffles them
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


	var pitch: float = item.pitch if typeof(item) == TYPE_DICTIONARY and item.has("pitch") else 1.0
	player.stream = load(stream_path)
	player.pitch_scale = randf_range(0.9, 1.1) * pitch

	if use_3d and pos != null:
		player.global_position = pos

	player.play()


# pitch multiplies the usual random variation: below 1.0 is deeper, above is higher
func play(sound_paths: String, pitch := 1.0) -> void:
	var list := sound_paths.split(",")
	var chosen := list[randi() % list.size()].strip_edges()
	if is_equal_approx(pitch, 1.0):
		queue.append("res://" + chosen)
	else:
		queue.append({"path": "res://" + chosen, "pitch": pitch})


func play_at(position: Vector3, sound_paths: String, pitch := 1.0) -> void:
	var list := sound_paths.split(",")
	var chosen := list[randi() % list.size()].strip_edges()
	var path := "res://" + chosen

	if use_3d:
		queue.append({"path": path, "pos": position, "pitch": pitch})
	else:
		_play_one_shot_3d(path, position, pitch)


# The 2D pool (the Audio autoload) can't place a sound in the world, so it gets a positional player of its own
func _play_one_shot_3d(path: String, position: Vector3, pitch := 1.0) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = load(path)
	player.bus = bus
	player.volume_db = -10
	player.pitch_scale = randf_range(0.9, 1.1) * pitch
	player.unit_size = 6.0
	player.max_distance = 60.0
	player.attenuation_filter_db = 0.0
	player.finished.connect(player.queue_free)
	add_child(player)
	player.global_position = position
	player.play()
