extends LevelBase

# Level built from trenchbroom/maps/level_01.map. The building and baking are in LevelBase.


func _level_ready() -> void:
	# The controls window, on a fresh start of the level (not when coming back from a checkpoint further on)
	if Checkpoints.current == null or Checkpoints.current.checkpoint_id.is_empty():
		ControlsHint.show_at_start(self, player)
