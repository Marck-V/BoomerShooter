extends Node3D
class_name BasePickup

@export_enum("Health", "Ammo", "Points") var type: String
@export_category("Weapon Type") 
@export_enum("pistol","shotgun","rifle") var weapon_id: String ## Only assign this if this is an Ammo pickup
@export_category("Variables")
@export var points_amount = 500
@export var healing_amount = 25
@export var ammo_amount = 100
@onready var mesh_instance_3d: MeshInstance3D = $MeshInstance3D

var model_scale = Vector3.ONE
var gold_bar_scale_factor = 0.1
var health_scale_factor = 0.5
var ammo_scale = 2

var base_y = 0.0
var t = 0.0

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
	"Health": Vector3(health_scale_factor, health_scale_factor, health_scale_factor),
	"Ammo": Vector3(ammo_scale, ammo_scale, ammo_scale),
	"Points": Vector3(gold_bar_scale_factor, gold_bar_scale_factor, gold_bar_scale_factor)
}

var model_instance: Node3D


func _ready() -> void:
	mesh_instance_3d.visible = false
	base_y = position.y
	_build_model()


# Pickups placed from a map entity get their properties (type, weapon_id...) after _ready has already run,
# so the model is rebuilt then; otherwise every map pickup would show the scene's default type.
func _func_godot_apply_properties(_properties: Dictionary) -> void:
	if is_node_ready():
		_build_model()


func _build_model() -> void:
	if model_instance:
		model_instance.queue_free()
		model_instance = null
	var model_scene
	if type == "Ammo":
		model_scene = load(ammo_paths[weapon_id]) if ammo_paths.has(weapon_id) else load(ammo_paths["shotgun"])
	else:
		model_scene = load(model_paths[type]) if model_paths.has(type) else load(model_paths["Points"])
	model_instance = model_scene.instantiate()
	model_instance.scale = scale_map.get(type, scale_map["Points"])
	add_child(model_instance)


func _process(delta):
	t += delta

	rotate_y(0.5 * delta)
	position.y = base_y + sin(t) * 0.1
	rotation.x = sin(t * 1.3) * 0.05
	rotation.z = sin(t * 1.7) * 0.05
	
func _on_area_3d_body_entered(body: Node3D) -> void:
	if not body.is_in_group("Player"):
		return
		
	match type:
		"Ammo":
			GlobalVariables.add_ammo(weapon_id, ammo_amount)
			Audio.play("assets/sounds/reload.mp3")
		"Health":
			GlobalVariables.add_health(healing_amount)
			Audio.play("assets/sounds/health_pickup.mp3")
		"Points":
			GlobalVariables.add_points(points_amount)
			Audio.play("assets/sounds/money_pickup.mp3")
	
	queue_free()
