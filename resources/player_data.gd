extends Resource
class_name PlayerData

# --- Gameplay Progress ---
@export var points: int = 0

@export var upgrades: Dictionary = {
	"pistol_dead_eye": false,
	"pistol_piercing": false,
	"pistol_lifesteal": false,

	"shield_retaliation": false,

	"flamethrower_pressure": false,
	"flamethrower_accelerant": false,
	"flamethrower_backdraft": false,

	"shotgun_precision": false,
	"shotgun_shield_break": false,
	"shotgun_glitch_shot": false,

	"rifle_firerate": false,
	"rifle_quickness": false,
	"rifle_conductor": false,

	"lightning_chain_reaction": false,
	"lightning_conduit": false
}

# What the player has been given so far: weapon ids and "shield". A new story starts with the pistol only (see
# GlobalVariables.UNLOCKABLE for the full list)
@export var unlocked: Dictionary = {
	"pistol": true,
}

@export var ammo: Dictionary = {
	"pistol": 50,
	"shotgun": 50,
	"rifle": 50,
	"flamethrower": 50,
	"lightning": 15
}


# --- Player Settings ---
@export var settings: Dictionary = {
	"music_volume": 0.2,          # 0.0–1.0
	"sfx_volume": 0.2,            # 0.0–1.0
	"mouse_sensitivity": 10.0,    # 0–100
	"fullscreen": false
}
