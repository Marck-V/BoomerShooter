extends Resource
class_name PlayerData

# --- Gameplay Progress ---
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


# --- Player Settings ---
@export var settings: Dictionary = {
	"music_volume": 0.2,          # 0.0–1.0
	"sfx_volume": 0.2,            # 0.0–1.0
	"mouse_sensitivity": 10.0,    # 0–100
	"fullscreen": false
}
