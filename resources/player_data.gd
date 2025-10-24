extends Resource
class_name PlayerData

@export var points: int = 0
@export var upgrades: Dictionary = {
	"pistol_ammo_refund": false,
	"pistol_piercing": false,
	"pistol_lifesteal": false,

	"shotgun_precision": false,
	"shotgun_shield_break": false,
	"shotgun_glitch_shot": false,

	"rifle_firerate": false,
	"rifle_quickness": false,
	"rifle_chain_shot": false
}

@export var ammo: Dictionary = {
	"pistol": 50,
	"shotgun": 50,
	"rifle": 50
}
