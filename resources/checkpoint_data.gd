extends Resource
class_name CheckpointData

# A snapshot of a run, taken when the level starts and again at every checkpoint. Dying reloads the level and
# puts it back the way this recorded it. Every field is exported, so it can be written to disk with ResourceSaver
# as it is (see Checkpoints.save_to_disk).

@export var level_path := ""             # the scene this snapshot belongs to
@export var checkpoint_id := ""          # path of the checkpoint that took it; empty for the level start

# --- Where the player comes back ---
@export var spawn_position := Vector3.ZERO
@export var spawn_yaw := 0.0

# --- The player ---
@export var points := 0
@export var ammo: Dictionary = {}
@export var upgrades: Dictionary = {}
@export var keys := PackedStringArray()
@export var weapon_index := 0

# --- The level ---
@export var gone := PackedStringArray()                 # paths (from the level root) of pickups, keys and enemies already used up
@export var cleared_waves := PackedStringArray()
@export var reached_checkpoints := PackedStringArray()
