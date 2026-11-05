extends Node
class_name WaterRipple

# Rings spreading out across the water floor (shaders/environment/water_floor.gdshader) from a point, e.g. where the hand
# boss's finger touches it. The shader draws up to four at once; each ripple node ages its slot every frame and
# frees it when it has faded. A fifth takes over the oldest.
#   WaterRipple.spawn(get_tree(), point)                  a big ripple across the whole arena
#   WaterRipple.spawn(get_tree(), point, 0.5, 2.5)        a small, short one

const WATER: ShaderMaterial = preload("res://trenchbroom/textures/world/water.tres")
const SLOTS := 4

static var values: Array[Vector4] = [Vector4(0, 0, -1, 0), Vector4(0, 0, -1, 0), Vector4(0, 0, -1, 0), Vector4(0, 0, -1, 0)]
static var owners: Array = [null, null, null, null]

var slot := -1
var point := Vector3.ZERO
var strength := 1.0
var life := 5.0
var age := 0.0


static func spawn(tree: SceneTree, at: Vector3, ripple_strength := 1.0, ripple_life := 5.0) -> WaterRipple:
	var ripple := WaterRipple.new()
	ripple.point = at
	ripple.strength = ripple_strength
	ripple.life = ripple_life
	(tree.current_scene if tree.current_scene else tree.root).add_child(ripple)
	return ripple


func _ready() -> void:
	slot = _free_slot()
	owners[slot] = self
	_write()


func _process(delta: float) -> void:
	if owners[slot] != self:
		queue_free()   # a newer ripple took the slot
		return
	age += delta
	if age >= life:
		queue_free()
		return
	_write()


func _exit_tree() -> void:
	if slot >= 0 and owners[slot] == self:
		owners[slot] = null
		values[slot] = Vector4(0, 0, -1, 0)
		WATER.set_shader_parameter("touch_ripples", values)


func _write() -> void:
	var fading := 1.0 - age / life
	values[slot] = Vector4(point.x, point.z, age, strength * fading * fading)
	WATER.set_shader_parameter("touch_ripples", values)


# An empty slot, or failing that the one holding the oldest ripple
static func _free_slot() -> int:
	var oldest := 0
	var oldest_age := -1.0
	for i in SLOTS:
		var owner = owners[i]
		if owner == null or not is_instance_valid(owner):
			return i
		if owner.age > oldest_age:
			oldest_age = owner.age
			oldest = i
	return oldest
