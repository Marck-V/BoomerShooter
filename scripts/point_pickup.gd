extends Node3D
class_name BasePickup

@export_enum("Health", "Ammo", "Points") var type: String
@export_category("Ammo & Weapon")
@export_enum("pistol","shotgun","rifle") var weapon_id: String ## Only assign if the pickup type is ammo
@export_category("Points")
@export var points_amount = 500
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D
var model_scale = Vector3.ONE
var gold_bar_scale_factor = 0.1

var ammo_paths = {
	"pistol": "res://models/weapons/pistol_ammo_mesh.tscn",
	"shotgun": "res://models/weapons/shotgun_ammo_mesh.tscn",
	"rifle": "res://models/weapons/rifle_ammo_mesh.tscn"
}

var model_paths = {
	"Health": "res://models/meds_pizza.tscn",
	"Points" : "res://models/psx_gold_bar.tscn"
}

var scale_map = {
	"Health": Vector3(0.5,0.5,0.5),
	"Ammo": Vector3.ONE,
	"Points": Vector3(gold_bar_scale_factor,gold_bar_scale_factor,gold_bar_scale_factor)
}

func _ready() -> void:
	mesh_instance_3d.visible = false
	
	var model_scene
	var model_instance
	if type == "Ammo":
		model_scene = load(ammo_paths[weapon_id]) 
	else:
		model_scene = load(model_paths[type]) 
	
	model_instance = model_scene.instantiate()
	model_instance.scale = scale_map[type]
	add_child(model_instance)
	
func _on_area_3d_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return
		
	match type:
		"Ammo":
			GlobalVariables.add_ammo(weapon_id, 30)
			Audio.play("assets/sounds/reload.mp3")
		
		"Health":
			pass
		"Points":
			GlobalVariables.add_points(points_amount)
			Audio.play("assets/sounds/money_pickup.mp3")
	
	queue_free()
