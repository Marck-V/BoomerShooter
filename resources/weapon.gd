
extends Resource
class_name Weapon

@export_subgroup("Properties")
@export_range(0.1, 1) var cooldown: float = 0.1  # Firerate
@export_range(1, 20) var max_distance: int = 10  # Fire distance
@export_range(0, 100) var damage: float = 25  # Damage per hit
@export_range(0, 5) var spread: float = 0  # Spread of each shot
@export_range(1, 5) var shot_count: int = 1  # Amount of shots
@export_range(1,5) var recoil_strength: int = 1
@export var weapon_id : String



@export_subgroup("Sounds")
@export var sound: String

@export_subgroup("Crosshair")
@export var crosshair: Texture2D  # Image of crosshair on-screen
