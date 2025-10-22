extends CharacterBody3D
class_name EnemyBase

# --- Common Enemy Properties ---
@export var movement_speed: float = 6.0
@export var health: float = 100.0
@export var target: Node3D
@export var debug: bool = false

var shield: Node = null
var original_material: Material
var shield_material: ShaderMaterial = preload("res://shaders/glass_shader.tres")
var destroyed: bool = false
var attack_animation : String = "Attack"

# --- State Machine ---
var state = null
var states = {}

# --- References (set in subclasses) ---
@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var anim: AnimationPlayer = $"enemy-humanoid/AnimationPlayer"
@onready var model: MeshInstance3D = $"enemy-humanoid/Armature/Skeleton3D/HumanoidBase_NotOverlapping"

# ---------------------------
# Lifecycle
# ---------------------------
func _ready():
	states = get_state_definitions()
	change_state("Idle")
	make_mesh_materials_unique(model)
	cache_original_material()
	initialize_shield()

func _physics_process(delta):
	if state and state.has_method("update"):
		state.update(delta)

# ---------------------------
# Abstract Hooks (subclasses override)
# ---------------------------
func get_state_definitions() -> Dictionary:
	return {}

func perform_attack():
	pass

func can_attack() -> bool:
	return true

# ---------------------------
# Damage & Death
# ---------------------------
func damage(amount: float, multiplier: float = 1.0):
	if shield:
		amount = shield.absorb_damage(amount)
	else:
		amount *= multiplier

	health -= amount
	if health <= 0 and not destroyed:
		change_state("Dead")

# ---------------------------
# Shield Visuals
# ---------------------------
func initialize_shield():
	if has_node("Shield"):
		shield = $Shield
		shield.connect("shield_destroyed", Callable(self, "_on_destroyed"))
		apply_shield_material()

func _on_destroyed():
	remove_shield_material()

func apply_shield_material():
	if has_node("ShieldShader"):
		$ShieldShader.visible = true
	model.set_surface_override_material(0, shield_material)

func remove_shield_material():
	if has_node("ShieldShader"):
		$ShieldShader.visible = false
	model.set_surface_override_material(0, original_material)

func make_mesh_materials_unique(mesh_instance: MeshInstance3D):
	var mesh = mesh_instance.mesh.duplicate()
	for i in range(mesh.get_surface_count()):
		var mat = mesh.surface_get_material(i)
		if mat:
			mesh.surface_set_material(i, mat.duplicate())
	mesh_instance.mesh = mesh

func cache_original_material():
	if model.get_surface_override_material(0):
		original_material = model.get_surface_override_material(0)
	else:
		original_material = model.mesh.surface_get_material(0)

# ---------------------------
# State Management
# ---------------------------
func change_state(state_name: String):
	if not states.has(state_name):
		return
	if state and state.has_method("exit"):
		state.exit()
	state = states[state_name]
	if state and state.has_method("enter"):
		state.enter()
