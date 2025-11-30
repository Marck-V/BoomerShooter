extends CharacterBody3D
class_name EnemyBase

# --- Common Enemy Properties ---
@export var movement_speed: float = 6.0
@export var rotation_speed: float = 5.0
@export var health: float = 100.0
@export var target: Node3D
@export var debug: bool = false

var shield: Node = null
var original_materials: Array[Material] = []
var shield_material: ShaderMaterial = preload("res://shaders/glass_shader.tres")
var destroyed: bool = false

var attack_animation_enter: String = ""
var attack_animation_action: String = "Sword_Attack"
var attack_animation_exit: String = ""
var attack_idle_animation: String = "Idle"

var is_attacking := false

# --- State Machine ---
var state = null
var states = {}

# --- References (set in subclasses) ---
@onready var nav: NavigationAgent3D = $NavigationAgent3D
@onready var anim: AnimationPlayer = $"Enemy_Model/AnimationPlayer"
@onready var model: MeshInstance3D = $"Enemy_Model/Rig/Skeleton3D/Mannequin"
@onready var attack_start_cooldown: Timer = $AttackStartCooldown
@onready var audio_player: Node3D = $"AudioPlayer"

# --- Shield ---
@export var has_shield: bool = false
const SHIELD_SCENE: PackedScene = preload("res://scenes/enemies/shield.tscn")

# Signal
#signal enemy_died(enemy: EnemyBase)

# ---------------------------
# Lifecycle
# ---------------------------
func _ready():
	states = get_state_definitions()
	change_state("Idle")
	make_mesh_materials_unique(model)
	cache_original_materials()
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

func is_in_attack_range() -> bool:
	return false  # default, overridden by specific enemies


# ---------------------------
# Damage & Death
# ---------------------------
func damage(amount: float, multiplier: float = 1.0):
	var dmg := amount * multiplier
	if shield:
		dmg = shield.absorb_damage(dmg)
	
	health -= clamp(dmg, 0.0, health)
	#print("Enemy took damage: ", dmg, " Remaining health: ", health)
	if health <= 0.0 and not destroyed:
		GlobalVariables.enemy_died.emit(self)
		change_state("Dead")


# ---------------------------
# Unified Shield Initialization
# ---------------------------
func initialize_shield():
	if not has_shield:
		return

	# Check for pre-placed Shield or spawn one
	if has_node("Shield"):
		shield = $Shield
	else:
		var shield_scene = SHIELD_SCENE.instantiate()
		shield_scene.name = "Shield"
		add_child(shield_scene)
		shield = shield_scene

	# Connect once
	if shield.has_signal("shield_destroyed") and not shield.is_connected("shield_destroyed", Callable(self, "_on_shield_destroyed")):
		shield.connect("shield_destroyed", Callable(self, "_on_shield_destroyed"))

	apply_shield_material()

func _on_shield_destroyed():
	remove_shield_material()
	shield = null


# ---------------------------
# Material Handling
# ---------------------------
func apply_shield_material():
	#if has_node("ShieldShader"):
		#$ShieldShader.visible = true
	var mesh := model.mesh
	for i in range(mesh.get_surface_count()):
		model.set_surface_override_material(i, shield_material)

func remove_shield_material():
	#if has_node("ShieldShader"):
		#$ShieldShader.visible = false
	var mesh := model.mesh
	for i in range(min(mesh.get_surface_count(), original_materials.size())):
		model.set_surface_override_material(i, original_materials[i])


# ---------------------------
# Safe Mesh Duplication
# ---------------------------
func make_mesh_materials_unique(mesh_instance: MeshInstance3D):
	var old_mesh := mesh_instance.mesh
	if old_mesh == null:
		return
	
	var new_mesh := ArrayMesh.new()
	for i in range(old_mesh.get_surface_count()):
		var surface_arrays := old_mesh.surface_get_arrays(i)
		var mat := old_mesh.surface_get_material(i)
		new_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
		if mat:
			new_mesh.surface_set_material(i, mat.duplicate())
	mesh_instance.mesh = new_mesh


# ---------------------------
# Cache Original Materials
# ---------------------------
func cache_original_materials():
	original_materials.clear()
	var mesh := model.mesh
	for i in range(mesh.get_surface_count()):
		var override := model.get_surface_override_material(i)
		if override:
			original_materials.append(override)
		else:
			original_materials.append(mesh.surface_get_material(i))


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
