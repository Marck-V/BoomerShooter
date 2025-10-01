extends Resource
class_name PlayerData

@export var points: int = 0
@export var upgrades: Dictionary = {
	"pistol_upgrade1" : false,
	"pistol_upgrade2" : false,
	"pistol_upgrade3" : false
}
@export var ammo: Dictionary = {
	"pistol": 50,
	"shotgun": 50,
	"rifle": 50
}
