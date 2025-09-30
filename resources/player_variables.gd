extends Resource
class_name PlayerVariables

@export var points: int = 0
@export var upgrades: Dictionary = {
	"blaster_damage" : false,
	"blaster_damage2" : false,
	"blaster_damage3" : false
}
@export var ammo: Dictionary = {
	"pistol_bullets": 0,
	"shotgun_shells": 0,
	"rifle_bullets": 0
}
