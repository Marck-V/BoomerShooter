extends Control

# File paths for each weapon
var blaster : Weapon = load("res://weapons/blaster.tres")
var repeater : Weapon = load("res://weapons/blaster-repeater.tres")
var damage_increase = 5
const BLASTER_PATH = "res://weapons/blaster.tres"
@onready var pistol_button_1: UpgradeButton = $PistolButton1
@onready var pistol_button_2: UpgradeButton = $PistolButton1/PistolButton2
@onready var pistol_button_3: UpgradeButton = $PistolButton1/PistolButton2/PistolButton3



func _on_pistol_button_1_pressed() -> void:
	blaster.damage += damage_increase
	ResourceSaver.save(blaster, BLASTER_PATH)
	print("Pistol damage upgraded by:", damage_increase)


func _on_reset_button_pressed() -> void:
	blaster.damage = 25
	ResourceSaver.save(blaster, BLASTER_PATH)
