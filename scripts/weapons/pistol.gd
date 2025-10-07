extends BaseWeapon

var refund = "pistol_ammo_refund"
var piercing = "pistol_piercing"
var lifesteal = "pistol_lifesteal"

var has_ammo_refund = false
var has_piercing = false
var has_lifesteal = false

var refund_chance = 0.10

func _ready() -> void:
    super._ready()
    GlobalVariables.upgrade_purchased.connect(on_upgrade_purchased)
    _refresh_upgrades()

func fire(origin: Vector3, _direction: Vector3, camera: Camera3D, raycast: RayCast3D):
    super.fire(origin, _direction, camera, raycast)
    if has_ammo_refund and randf() < refund_chance:
        GlobalVariables.add_ammo("pistol", 10)
        Audio.play("assets/sounds/reload.mp3")
        print("Pistol Ammo Refunded")
    
func _refresh_upgrades() -> void:
    has_ammo_refund = GlobalVariables.has_upgrade(refund)
    has_piercing = GlobalVariables.has_upgrade(piercing)
    has_lifesteal = GlobalVariables.has_upgrade(lifesteal)
    
func on_upgrade_purchased(upgrade_id: String) -> void:
    if upgrade_id == refund:
        has_ammo_refund = true
        print("Pistol Ammo Refund Active")    
    elif upgrade_id == piercing:
        has_piercing = true
        print("Pistol Piercing Active")
    elif upgrade_id == lifesteal:
        has_lifesteal = true
        print("Pistol Lifesteal Active")