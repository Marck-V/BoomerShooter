extends Resource
class_name PlayerData

@export var points: int = 0
@export var upgrades: Dictionary = {
	"blaster_damage" : false,
	"blaster_damage2" : false,
	"blaster_damage3" : false
}
@export var ammo: Dictionary = {
	"pistol": 50,
	"shotgun": 50,
	"rifle": 50
}
